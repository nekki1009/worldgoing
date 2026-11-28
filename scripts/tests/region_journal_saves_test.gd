extends SceneTree
## A scenario world keeps saving and reopening over the days (2026-11-25): its unopened Sites pin the fire clock journal, and
## the commit record used to pass the size it could be read back with after one or two game days (SAVE_IO for every later
## save). A small generated scenario world (6 settlements, 3 bands, 1 town) runs five game days at speed 16, saved once a
## day. Checks:
## - every save goes through (each one reads the one before it back) and its record stays small;
## - the journal keeps only its exact part once it is compacted;
## - a village nobody opened is bound after five days by the long-absence steps (the coarse prefix, no fallback to exact
##   replay), its people are there, and the world goes on;
## - the same slot opens anew from its files.
## Output: REGION_JOURNAL_SAVES_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const DAY := 86400.0

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(3400.0).timeout.connect(func() -> void: _fail("3400-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_JOURNAL_SAVES_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_JOURNAL_SAVES OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _run() -> void:
	var folder := "user://journal_saves_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "存檔多日", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 1200000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	lab.simulation_speed = 16.0
	var village := ""
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var people := 0
		for army: Variant in loaded.data.site.get("armies", []): people += army.get("units", []).size()
		if people < 30 and village.is_empty(): village = "%s:%s" % [str(slot.pin.atlas_id), str(site)]
	if not _ok(not village.is_empty(), "the village %s is watched" % village): return
	var began := float(slot.control.logical_game_seconds)
	var sizes: Array = []
	for day: int in range(1, 6):
		var frames := 0
		var day_ms := Time.get_ticks_msec()
		while float(slot.control.logical_game_seconds) - began < float(day) * DAY:
			if not await _frame(): return
			frames += 1
			if frames > 20000: break
		if not _ok(float(slot.control.logical_game_seconds) - began >= float(day) * DAY, "game day %d is reached (%d frames, %.1f ms each)" % [day, frames, float(Time.get_ticks_msec() - day_ms) / float(maxi(1, frames))]): return
		var rows: int = slot.control.fire_clock.journal.size()
		var saved: Dictionary = {"ok": false}
		for attempt: int in range(60): # a save waits for the Site's own rest
			saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
			if saved.get("ok", false): break
			if not await _frame(): return
		var path: String = slot.folder.path_join("commits/%020d.json" % int(slot._marker.generation))
		var bytes := FileAccess.get_file_as_bytes(path).size()
		sizes.append(bytes)
		print("REGION_JOURNAL_SAVES DAY %d rows %d -> %d record %d bytes raids %s" % [day, rows, slot.control.fire_clock.journal.size(), bytes, JSON.stringify(slot.get_meta(&"bandit_formula_last", {})).left(300)])
		if not _ok(saved.get("ok", false), "day %d is saved" % day, saved): return
	if not _ok(int(sizes[4]) < int(sizes[2]) * 2, "the record no longer grows with the days", sizes): return
	if not _ok(int(sizes[4]) < 8 * 1024 * 1024, "and stays small", sizes): return

	# The village, five days later: the long-absence steps, not the exact replay.
	lab.set_process(false)
	var bound: Dictionary = {}
	var isolated: Dictionary = {}
	var averaged := false
	var bind_ms := Time.get_ticks_msec()
	for attempt: int in range(20000):
		bound = lab._region_gameplay_owner_lab(village, "cold_exact")
		if is_instance_valid(lab._cold_replay_lab):
			isolated = lab._cold_replay_lab._region_cold_isolated.duplicate()
			averaged = averaged or not lab._cold_replay_lab._fire_replay_boundaries_unrecoverable
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	print("REGION_JOURNAL_SAVES BIND ok=%s code=%s %d ms coarse=%s prefix_steps=%s exact_steps=%s fallback=%s" % [str(bound.get("ok")), str(bound.get("code", "")), Time.get_ticks_msec() - bind_ms,
		str(isolated.get("coarse")), str(isolated.get("prefix_steps")), str(isolated.get("exact_steps")), str(isolated.get("fallback", ""))])
	if not _ok(bound.get("ok", false), "the village is bound after five days", bound): return
	if not _ok(averaged and bool(isolated.get("coarse", false)) and int(isolated.get("prefix_steps", 0)) > 20, "by the long-absence steps", isolated): return
	if not _ok(bound.lab.crowd_site._index_by_id.size() > 3, "its people are there: %d" % bound.lab.crowd_site._index_by_id.size()): return
	var on_from := float(slot.control.logical_game_seconds)
	for frame: int in range(2000):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - on_from > 7200.0: break
	if not _ok(float(slot.control.logical_game_seconds) - on_from > 7200.0, "two hours go on with it"): return

	# The slot opens anew from its files.
	var last: Dictionary = {"ok": false}
	for attempt: int in range(60):
		last = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if last.get("ok", false): break
		if not await _frame(): return
	if not _ok(last.get("ok", false), "saved once more", last): return
	var read: Dictionary = slot._read_document(slot.folder.path_join("commits/%020d.json" % int(slot._marker.generation)), slot.COMMIT_DOCUMENT_BYTES)
	if not _ok(read.get("ok", false), "the last record reads back", read.get("code", "")): return
	var recovered: Dictionary = slot._recover_read_latest(false, {})
	if not _ok(recovered.get("ok", false) and int(recovered.recorded.generation) == int(slot._marker.generation), "the slot recovers from its files", recovered.get("code", "")): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_JOURNAL_SAVES_PASS: ", checks, " checks")
	quit(0)
