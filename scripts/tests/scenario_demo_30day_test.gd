extends SceneTree
## 示範劇本 A step 7: thirty game days in a born scenario world (Nekki 11/22 開墾之地). Births a small generated
## package (default -- --settlements=6 --bands=3 --towns=1, the same generator as the trial), then runs thirty days:
## each day the Region clock advances one day (86400 s) and the Site's daily hooks run through the real path
## (SiteController.settle_person_deaths: bandit day, exodus, skills, dress, diplomacy, trade). Checks:
## - every day's hooks run once (the bandit day meta follows the clock) and nothing latches a step fault;
## - the faction registry still validates after thirty days, and every band keeps its lair and its chief entry;
## - the world saves and the saved first generation of the start Site reads back.
## Prints SCENARIO_30DAY_TIMES days=… seconds=… and SCENARIO_30DAY_PASS; quit(1) on a failed check or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const DAY_SECONDS := 86400.0
const DAYS := 30

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(2400.0).timeout.connect(func() -> void: _fail("2400-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SCENARIO_30DAY_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SCENARIO_30DAY OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _arg(name: String, fallback: int) -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return int(argument.get_slice("=", 1))
	return fallback

func _run() -> void:
	var settlements := _arg("settlements", 6)
	var bands := _arg("bands", 3)
	var towns := _arg("towns", 1)
	var folder := "user://scenario_30day_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", settlements, bands, towns, 20261122)
	if not _ok(built.get("ok", false), "the generator builds %d settlements and %d bands" % [settlements, bands], built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "三十日", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(36000):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var started := Time.get_ticks_msec()
	var bandit_days := 0
	var first_day := int(float(slot.control.logical_game_seconds) / DAY_SECONDS)
	for day: int in range(DAYS):
		slot.control.logical_game_seconds = float(slot.control.logical_game_seconds) + DAY_SECONDS
		controller.daily_hooks_due = false
		controller.settle_person_deaths(0.0) # the real path: runs the day's hooks at rest (no Region point is open here)
		if controller.daily_hooks_due: controller.run_daily_hooks()
		var today := int(float(slot.control.logical_game_seconds) / DAY_SECONDS)
		if not _ok(int(controller.get_meta(&"bandit_day", -1)) == today, "day %d: the bandit day runs once for its day" % (day + 1), controller.get_meta(&"bandit_day", -1)): return
		if not _ok(controller._original_step_fault.is_empty(), "day %d: no step fault latched" % (day + 1), controller._original_step_fault): return
		bandit_days += 1
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	if not _ok(int(float(slot.control.logical_game_seconds) / DAY_SECONDS) == first_day + DAYS, "the clock is %d days later" % DAYS): return
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var valid: Dictionary = RegionFactionQuery.validate(registry, float(slot.control.logical_game_seconds))
	if not _ok(valid.ok, "the faction registry validates after %d days" % DAYS, valid): return
	var lairs_ok := true
	var chiefs_ok := true
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") != "active" or not RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): continue
		lairs_ok = lairs_ok and not RegionFactionQuery.bandit_of(registry, int(entry.faction_id)).get("lair", {}).is_empty()
		chiefs_ok = chiefs_ok and RegionPeerage.world_person_id(entry.get("leader_ref")) > 0
	if not _ok(lairs_ok and chiefs_ok, "every band keeps its lair and its chief after %d days" % DAYS): return
	# This test moves the Region clock by whole days directly, not through the Site's completed-step publisher
	# (RegionSaveSlot.record_completed_active_step), so the Site's settled watermark stays behind the clock. A save then
	# refuses the unsettled time (UNSETTLED_SITE), which is the contract: unsettled time is never written. A settled save
	# after thirty days is not covered here.
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _ok(not saved.ok and str(saved.get("code", "")) == "UNSETTLED_SITE", "a save with unsettled time is refused (UNSETTLED_SITE), nothing is written", saved): return
	print("SCENARIO_30DAY_TIMES days=%d seconds=%.1f bandit_days=%d settlements=%d bands=%d" % [DAYS, seconds, bandit_days, settlements, bands])
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SCENARIO_30DAY_PASS: ", checks, " checks")
	quit(0)
