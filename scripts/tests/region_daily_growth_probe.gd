extends SceneTree
## Probe (2026-11-25): does a Region world cost more per frame as the game days pass? A quick new world (founded faction,
## the player idle) runs at speed 16, and every quarter game day writes one line to the progress file given with
## `--progress=<absolute path>`: milliseconds per frame, the step profile's biggest stages of that quarter, and the size of
## the world's tables. `--days=N` (default 3). Output: REGION_DAILY_GROWTH lines and REGION_DAILY_GROWTH_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const START := Vector2i(1170, 13252)
const DAY := 86400.0

var lab: TerrainLab
var progress_path := ""
var finished := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--progress="): progress_path = arg.trim_prefix("--progress=")
	create_timer(3300.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _end(reason: String) -> void:
	if finished: return
	finished = true
	_say("REGION_DAILY_GROWTH END %s" % reason)
	print("REGION_DAILY_GROWTH_DONE")
	quit(0)

func _say(text: String) -> void:
	print(text)
	if progress_path.is_empty(): return
	var file := FileAccess.open(progress_path, FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open(progress_path, FileAccess.WRITE)
	if file == null: return
	file.seek_end()
	file.store_line(text)
	file.close()

func _arg(name: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return float(arg.trim_prefix("--%s=" % name))
	return fallback

func _size(value: Variant) -> int:
	return var_to_bytes(value).size()

func _run() -> void:
	# --scenario: the small generated scenario world (6 settlements, 3 bands, 1 town), nobody visits its other Sites.
	if OS.get_cmdline_user_args().has("--scenario"):
		var folder := "user://growth_%d" % OS.get_process_id()
		DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
		var natural := RegionData.new()
		natural.load_manifest(RegionData.DEFAULT_MANIFEST)
		var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
		if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "成長探針劇本", "", str(built.path)):
			_end("no scenario world")
			return
	elif not RegionEntry.request_new_world(START, {}, "成長探針", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}):
		_end("no world")
		return
	change_scene_to_file(SITE)
	for _frame: int in range(900000):
		await process_frame
		if finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("the world did not open")
		return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	# --bind: the other Sites of the world are bound as cold owners first, as a raid or a visit does (nothing unbinds them).
	if OS.get_cmdline_user_args().has("--bind"):
		lab.set_process(false) # the world stands still while a Site is caught up, as at an arrival (a replay has one fixed target)
		var targets: Array = slot._marker.sites.keys()
		for key: Variant in targets:
			var parts: PackedStringArray = str(key).split(":")
			if parts.size() != 2: continue
			var id := "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
			if id == str(lab.terrain.site.id): continue
			if slot._region_original_labs.size() >= int(_arg("bind-max", 99.0)): break
			var bind_began := Time.get_ticks_msec()
			var bound: Dictionary = {}
			var attempts := 0
			var inside_usec := 0
			var longest_usec := 0
			for attempt: int in range(4000):
				var slice_began := Time.get_ticks_usec()
				bound = lab._region_gameplay_owner_lab(id, "cold_exact")
				var slice := Time.get_ticks_usec() - slice_began
				inside_usec += slice
				longest_usec = maxi(longest_usec, slice)
				attempts += 1
				if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
				await process_frame
			var traced: Dictionary = preload("res://scripts/terrain_lab/perf_trace.gd").flush("bind")
			if not traced.is_empty():
				var step_rows: Array = []
				for step: String in traced.steps: step_rows.append([float(traced.steps[step]), step])
				step_rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
				var shown_steps: Array = []
				for row: Array in step_rows.slice(0, 14): shown_steps.append("%s=%.0f" % [row[1], row[0]])
				_say("REGION_DAILY_GROWTH TRACE %s total=%.0f | %s" % [id, float(traced.total_ms), ", ".join(shown_steps)])
			_say("REGION_DAILY_GROWTH SLICES %s attempts=%d inside_ms=%.0f longest_ms=%.0f" % [id, attempts, float(inside_usec) / 1000.0, float(longest_usec) / 1000.0])
			_say("REGION_DAILY_GROWTH BIND %s ok=%s code=%s took_ms=%d" % [id, str(bound.get("ok")), str(bound.get("code", "")), Time.get_ticks_msec() - bind_began])
		lab.set_process(true)
		for owner: Variant in slot._region_original_labs: slot._region_original_labs[owner].combat_profile_enabled = true
		if OS.get_cmdline_user_args().has("--micro"):
			for owner: Variant in slot._region_original_labs:
				var cold: TerrainLab = slot._region_original_labs[owner]
				var Housing: Script = load("res://scripts/terrain_lab/site_housing.gd")
				var runs := {
					"coordinate": func() -> void: slot._coordinate(cold.terrain),
					"fire_settlement": func() -> void: RegionSaveSlot.validate_fire_settlement(cold.terrain.site, slot.control.fire_clock),
					"fire_activity": func() -> void: cold._fire_activity(),
					"attendance": func() -> void: Housing.call("attendance_input", cold),
					"recovery": func() -> void: for roster: Dictionary in cold.crowd_site.rosters: Housing.call("recovery_multiplier", cold, roster.units),
					"garrison": func() -> void: for roster: Dictionary in cold.crowd_site.rosters: cold.crowd_site.Site.Garrison.recovery_multiplier(cold, str(roster.get("garrison_feature_id", "")), int(roster.faction_id), roster.units),
					"capture_sample": func() -> void: cold.site_controller.Settlement.capture_sample(cold),
					"person": func() -> void: for identity: Variant in cold.crowd_site._index_by_id: cold.site_controller.person_actions._person(int(identity), false),
					"collect": func() -> void: cold._collect_original_shared_work_requests(1.0 / 30.0, 2.0, 1.0 / 30.0, 0.0),
					"siege_people": func() -> void: cold._siege_people(),
				}
				var line: Array = []
				for name: String in runs:
					var t0 := Time.get_ticks_usec()
					for _n: int in range(20): runs[name].call()
					line.append("%s=%.2fms" % [name, float(Time.get_ticks_usec() - t0) / 20000.0])
				_say("REGION_DAILY_GROWTH MICRO %s people=%d housing=%d features=%d | %s" % [str(owner), cold.crowd_site._index_by_id.size(), cold.terrain.site.get("housing", {}).size(), cold.terrain.site.get("features", {}).size(), ", ".join(line)])
			_end("micro")
			return
		_say("REGION_DAILY_GROWTH BOUND %d" % slot._region_original_labs.size())
	lab.simulation_speed = 16.0
	lab.combat_profile_enabled = true
	var began := float(slot.control.logical_game_seconds)
	var last_quarter := 0
	var quarter_ms := Time.get_ticks_msec()
	var frames := 0
	var before: Dictionary = {}
	while not finished:
		await process_frame
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		frames += 1
		if not controller._original_step_fault.is_empty():
			_end("step fault %s" % str(controller._original_step_fault).left(200))
			return
		var quarter := int((float(slot.control.logical_game_seconds) - began) / (DAY / 4.0))
		if quarter == last_quarter: continue
		last_quarter = quarter
		var spent := Time.get_ticks_msec() - quarter_ms
		var rows: Array = []
		for stage: String in lab.combat_profile_usec:
			rows.append([int(lab.combat_profile_usec[stage]) - int(before.get(stage, 0)), stage])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		before = lab.combat_profile_usec.duplicate()
		var top: Array = []
		for row: Array in rows.slice(0, 9): top.append("%s=%.0fms" % [row[1], float(row[0]) / 1000.0])
		var control: Dictionary = slot.control
		var sizes: Array = []
		for key: Variant in control: sizes.append([_size(control[key]), str(key)])
		sizes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var shown: Array = []
		for row: Array in sizes.slice(0, 5): shown.append("%s=%d" % [row[1], row[0]])
		var fire: Dictionary = control.get("fire_clock", {})
		# What keeps the journal's first rows: the lowest indexed sequence, and how many Sites are at or near it.
		var lowest := int(fire.get("sequence", 0))
		for identity: Variant in fire.get("index", {}): lowest = mini(lowest, int(fire.index[identity].sequence))
		var pinned := 0
		for identity: Variant in fire.get("index", {}):
			if int(fire.index[identity].sequence) == lowest: pinned += 1
		_say("REGION_DAILY_GROWTH quarter=%d day=%.2f real_s=%.1f frames=%d ms_per_frame=%.2f | %s | sizes %s | journal rows %d base %d seq %d index %d lowest %d (%d Sites there) site bytes %d notices %d mem_mb %.0f" % [quarter, float(quarter) / 4.0, float(spent) / 1000.0, frames, float(spent) / maxf(1.0, float(frames)), ", ".join(top),
			", ".join(shown), fire.get("journal", []).size(), int(fire.get("base_sequence", -1)), int(fire.get("sequence", -1)), fire.get("index", {}).size(), lowest, pinned, _size(lab.terrain.site), lab.terrain.site.get("notices", []).size(), float(OS.get_static_memory_usage()) / 1048576.0])
		for owner: Variant in slot._region_original_labs:
			var cold: TerrainLab = slot._region_original_labs[owner]
			var cold_rows: Array = []
			for stage: String in cold.combat_profile_usec: cold_rows.append([int(cold.combat_profile_usec[stage]), stage])
			cold_rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
			var cold_top: Array = []
			for row: Array in cold_rows.slice(0, 16): cold_top.append("%s=%.0f" % [row[1], float(row[0]) / 1000.0])
			_say("REGION_DAILY_GROWTH COLD %s total ms: %s" % [str(owner), ", ".join(cold_top)])
			cold.combat_profile_usec.clear()
		quarter_ms = Time.get_ticks_msec()
		frames = 0
		if float(quarter) / 4.0 >= _arg("days", 3.0): _end("reached")
