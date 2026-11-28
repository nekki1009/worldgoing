extends SceneTree
## 示範劇本 A step 7: a born scenario world over thirty bandit days (Nekki 11/22 開墾之地; Nekki 11/22 B for lair moves).
## Births a small generated package (default -- --settlements=6 --bands=3 --towns=1, the same generator as the trial). Checks:
## - natural play (120 frames) advances the world clock and a settled save after it is written and reads back;
## - thirty bandit day-passes (BanditDay.run day by day, at rest, the Region clock not jumped: a jump skips the step
##   boundaries that consume Region evaluation events and every registry commit is then refused) carry out every band
##   action: of two bands at heat 75, the one an official faction attacked moves its lair, the other lies low and stays;
## - the faction registry validates, every band keeps a lair and its chief, the world saves and reads back.
## Prints SCENARIO_30DAY_TIMES … and SCENARIO_30DAY_PASS; quit(1) on a failed check or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
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

## band id -> its lair Site id, for every active band of the registry.
func _lairs(registry: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(entry.faction_id)):
			result[int(entry.faction_id)] = str(RegionFactionQuery.bandit_of(registry, int(entry.faction_id)).get("lair", {}).get("site_id", ""))
	return result

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
	# Natural play first: the live Site steps in frames, its clock and settled watermark move together, so a save after
	# play time is a settled save (the real save path, not a clock shortcut).
	var play_before := float(slot.control.logical_game_seconds)
	for _frame: int in range(120):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty(): return _fail("a frame fault during play", controller._original_step_fault)
	var played := float(slot.control.logical_game_seconds) - play_before
	if not _ok(played > 0.0, "play time advances the world clock (%.1f s)" % played): return
	var settled: Dictionary = controller.save_to(controller.save_path)
	if not _ok(settled.ok, "a settled save after play time is written", settled): return
	var reread: Dictionary = slot._load_checked(slot.site_path(built.start), built.start)
	if not _ok(reread.get("ok", false), "the start Site's first generation reads back after play time"): return
	# Thirty bandit day-passes (Nekki 2026-11-22 B). The Region clock is not jumped: a jump skips the live step boundaries
	# that consume the Region evaluation events, and a registry commit is then refused (REGION_EFFECTS_PENDING) until a
	# step crosses them. Each pass runs the band decisions of one day (BanditDay.run, day by day) at rest with their
	# commits; the hottest two bands are set to heat 75 and the first of them is attacked by an official faction on
	# the first day: that band moves its lair, the other lies low and stays.
	var registry_before: Dictionary = slot.control.get("faction_registry", {})
	var hot: Array = []
	for key: Variant in registry_before.get("entries", {}):
		var entry: Dictionary = registry_before.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry_before, int(entry.faction_id)): hot.append(int(entry.faction_id))
	hot.sort()
	hot = hot.slice(0, 2)
	if not _ok(hot.size() == 2, "two bands to heat", hot): return
	for band: int in hot:
		var heated: Dictionary = Bandit.set_heat(slot.control.faction_registry, band, 75, float(slot.control.logical_game_seconds))
		if not _ok(heated.ok and controller._commit_diplomacy(heated, "").ok, "band %d is hot (heat 75)" % band, heated): return
	var first_day := int(float(slot.control.logical_game_seconds) / DAY_SECONDS) + 1
	Attacked.queue(controller, int(hot[0]), first_day)
	var attacked_saved: Dictionary = Attacked.flush(controller)
	if not _ok(attacked_saved.ok and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, int(hot[0])).get("attacked_day", -1)) == first_day,
		"an official attack on band %d is saved (heat +20, attacked day %d)" % [int(hot[0]), first_day], attacked_saved): return
	var lairs_start := _lairs(slot.control.faction_registry)
	var started := Time.get_ticks_msec()
	var counts := {}
	var refusals: Array = []
	for day: int in range(DAYS):
		var today := first_day + day
		controller.set_meta(&"bandit_day", today)
		var ran: Dictionary = BanditDay.run(controller, today)
		for row: Dictionary in ran.get("actions", []):
			var kind := str(row.get("action", ""))
			counts[kind] = int(counts.get(kind, 0)) + 1
			if not bool(row.get("ok", false)) and refusals.size() < 5: refusals.append(row)
		if not _ok(controller._original_step_fault.is_empty(), "day %d: no step fault latched" % (day + 1), controller._original_step_fault): return
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var lairs_end := _lairs(slot.control.faction_registry)
	print("SCENARIO_30DAY ACTIONS ", JSON.stringify(counts), " REFUSALS ", JSON.stringify(refusals))
	if not _ok(refusals.is_empty(), "every band action of the thirty days was carried out", refusals): return
	if not _ok(str(lairs_end.get(int(hot[0]), "")) != str(lairs_start.get(int(hot[0]), "")), "the attacked hot band moved its lair", [lairs_start, lairs_end]): return
	if not _ok(str(lairs_end.get(int(hot[1]), "")) == str(lairs_start.get(int(hot[1]), "")) and int(counts.get("lie_low", 0)) > 0, "the hot band nobody attacked lay low and stayed", counts): return
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var valid: Dictionary = RegionFactionQuery.validate(registry, float(slot.control.logical_game_seconds))
	if not _ok(valid.ok, "the faction registry validates after %d day-passes" % DAYS, valid): return
	var chiefs_ok := true
	for band: Variant in lairs_end:
		chiefs_ok = chiefs_ok and not str(lairs_end[band]).is_empty() and RegionPeerage.world_person_id(registry.entries[str(int(band))].get("leader_ref")) > 0
	if not _ok(chiefs_ok, "every band keeps a lair and its chief"): return
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _ok(saved.ok, "the world saves after the day-passes", saved): return
	var reread_days: Dictionary = slot._load_checked(slot.site_path(built.start), built.start)
	if not _ok(reread_days.get("ok", false), "the start Site's first generation reads back after the day-passes"): return
	var bandit_days := DAYS
	print("SCENARIO_30DAY_TIMES days=%d seconds=%.1f bandit_days=%d settlements=%d bands=%d play_seconds=%.1f" % [DAYS, seconds, bandit_days, settlements, bands, played])
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SCENARIO_30DAY_PASS: ", checks, " checks")
	quit(0)
