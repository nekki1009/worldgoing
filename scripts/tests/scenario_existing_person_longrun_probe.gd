extends SceneTree
## Probe (headless): a long idle run of the shipped demo A from a 選現成人物 start, to find step faults and a world that
## stands still. Births the package taking over the first person (or `--index=N`) of `-- --role=leader|head|chief|captain` (default
## leader), then runs at x16 for `--days=N` game days (default 5) with the player idle. Every game day it prints the day,
## the real seconds it took and the active Site; it fails on a step fault, or when the Region clock does not move for
## 3000 frames (a world standing still). Prints LONGRUN_PASS / LONGRUN_FAIL; quit(1) on failure or the deadline.
## `--profile`: TerrainLab's stage profile over the whole run, printed as the top 50 stages in seconds a game day.
## `--save-daily`: also save at every day's turn and fail on the first refusal.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

var _finished := false

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	create_timer(3300.0).timeout.connect(func() -> void: _fail("3300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	push_error("LONGRUN_FAIL %s %s" % [message, JSON.stringify(detail).left(1500) if detail != null else ""])
	TerrainArmy.release_contact_source()
	quit(1)

func _run() -> void:
	var role := _arg("role", "leader")
	var days := int(_arg("days", "5"))
	var person: Dictionary = {}
	var skip := int(_arg("index", "0")) # `--index=N`: the N-th person of the role (0 = the first), another Site
	for row: Dictionary in ScenarioPeople.people(PACKAGE).get("people", []):
		if str(row.role) != role: continue
		if skip > 0:
			skip -= 1
			continue
		person = row
		break
	if person.is_empty() or not RegionEntry.request_new_world(person.site, {"name": str(person.name)}, "長跑", "", PACKAGE, {"mode": "neutral"}, {"surname": str(person.name).left(1)}, {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}, [], {"name": str(person.name)}):
		return _fail("refused", RegionEntry.menu_message)
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null: return _fail("not born")
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	lab.simulation_speed = 16.0
	var first_day := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	var last_day := first_day
	var last_clock := float(slot.control.logical_game_seconds)
	var still := 0
	var started_ms := Time.get_ticks_msec()
	var day_ms := started_ms
	var frames := 0
	var save_due := -1 # the frame a daily save became due (`--save-daily`), -1 when none waits
	if "--profile" in OS.get_cmdline_user_args():
		lab.combat_profile_enabled = true
		lab.combat_profile_usec = {}
	print("LONGRUN %s %s at %s, day %d" % [role, str(person.name), str(person.site), first_day])
	for frame: int in range(4000000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		frames += 1
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			return _fail("a step fault on day %d" % (last_day - first_day), controller._original_step_fault)
		# An autosave refused for a broken state (not BUSY or a pending handoff) is shown on the Site only: fail on it.
		var refused: Variant = lab.get_meta(&"last_refused_result") if lab.has_meta(&"last_refused_result") else null
		if refused is Dictionary and str(refused.get("code", "")) in ["UNSTABLE_REGION_SNAPSHOT_JSON", "CORRUPT_SAVE", "SAVE_IO"]:
			return _fail("a save was refused on day %d" % (last_day - first_day), refused)
		if save_due >= 0:
			var daily: Dictionary = controller.save_to(controller.save_path)
			if daily.get("ok", false): save_due = -1
			elif str(daily.get("code", "")) != "BUSY": return _fail("the world does not save on day %d" % (last_day - first_day), daily)
			elif frame - save_due >= 6000: return _fail("the world stays BUSY for a save for 6000 frames on day %d" % (last_day - first_day), daily)
		var clock := float(slot.control.logical_game_seconds)
		if clock > last_clock:
			last_clock = clock
			still = 0
		else:
			still += 1
			if still == 300 or still >= 3000:
				# What the world waits on: the last refusal, a pending point or Region event, the Site's own clocks.
				var why := {"site": str(lab.terrain.site.get("id", "")), "pending": controller.region_operation_pending(), "paused": bool(lab.terrain.site.get("paused", false)),
					"tree_paused": paused, "minute": lab.terrain.site.get("minute"), "phase": lab.terrain.site.get("phase"), "combat_left": lab.terrain.site.get("combat_left"),
					"point_pending": lab._region_point_pending.keys(), "boot": controller._boot_request.keys(), "events": slot.pending_region_events().size(),
					"refused": lab.get_meta(&"last_refused_result") if lab.has_meta(&"last_refused_result") else null, "message": str(controller.message.text) if controller.message != null else ""}
				if still == 300: print("LONGRUN still for 300 frames on day %d (clock %.3f): %s" % [last_day - first_day, clock, JSON.stringify(why).left(3000)])
				else: return _fail("the world stands still on day %d (clock %.3f)" % [last_day - first_day, clock], why)
		var day := int(clock / Bandit.DAY)
		if day == last_day: continue
		last_day = day
		var now_ms := Time.get_ticks_msec()
		print("LONGRUN day %d in %.1f s (total %.0f s, %d frames), Site %s" % [day - first_day, float(now_ms - day_ms) / 1000.0, float(now_ms - started_ms) / 1000.0, frames, str(lab.terrain.site.get("id", ""))])
		day_ms = now_ms
		if day - first_day >= days: break
		# `--save-daily`: the world saves at every day's turn too (an autosave refusal names its cause at once). BUSY (a fall,
		# a walk or a relic hand-over under way) is asked again every frame, as the autosave does, for up to 6000 frames.
		if "--save-daily" in OS.get_cmdline_user_args(): save_due = frame
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not saved.get("ok", false): return _fail("the world does not save", saved)
	if lab.combat_profile_enabled:
		var stages: Array = lab.combat_profile_usec.keys()
		stages.sort_custom(func(x: Variant, y: Variant) -> bool: return float(lab.combat_profile_usec[x]) > float(lab.combat_profile_usec[y]))
		var run_days := maxf(1.0, float(last_day - first_day))
		for stage: Variant in stages.slice(0, 50): print("LONGRUN stage %s %.2f s a game day" % [str(stage), float(lab.combat_profile_usec[stage]) / 1000000.0 / run_days])
	print("LONGRUN_PASS %s %d days in %.0f s" % [role, last_day - first_day, float(Time.get_ticks_msec() - started_ms) / 1000.0])
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	quit(0)
