extends SceneTree
## Observation, not a pass / fail rule (2026-11-24): thirty game days of a small generated scenario world (6 settlements, 3
## bands, 1 town) run step by step at speed 16 with the player idle on the start Site. Nothing is forced: no receipts, no
## orders. Prints once a game day the formula raids, the bands, their heat, the band parties on the map, the bound Sites and the battle log,
## and at the end how many raids left, how many battles were fought and who died in them. `--days=N` (default 30).
## Output: RAID_30DAY lines and RAID_30DAY_DONE; quit(1) on a step fault or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(3480.0).timeout.connect(func() -> void: _fail("3480-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("RAID_30DAY_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("RAID_30DAY OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _days() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--days="): return int(arg.trim_prefix("--days="))
	return 30

func _run() -> void:
	var folder := "user://raid_30day_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "三十日觀察", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var open_deadline := Time.get_ticks_msec() + 1200000 # by the clock: beside another run the birth takes more frames
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var here := str(lab.terrain.site.id)
	var player := int(lab.controlled_person_id())
	var cadres: Array = []
	for person: Variant in _team_of(lab, player).get("person_ids", []):
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _ok(cadres.size() >= 5, "the player has five cadres", cadres): return
	lab.simulation_speed = 16.0
	var first_day := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	var last_day := first_day
	var parties_seen := {}
	var formula_raids := 0
	var formula_wins := 0
	var musters := 0
	var started_ms := Time.get_ticks_msec()
	var boot_ms := 0 # since the process started, birth included
	for frame: int in range(2000000):
		await process_frame
		if _finished: return
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		if not controller._original_step_fault.is_empty():
			_fail("a step fault on day %d" % (last_day - first_day), controller._original_step_fault)
			return
		var day := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
		for token: Variant in slot.region_registry().get("parties", {}):
			var party: Dictionary = slot.region_registry().parties[token]
			if not parties_seen.has(token): parties_seen[token] = Bandit.party_faction(party)
		if day == last_day: continue
		last_day = day
		var bands: Array = []
		for key: Variant in slot.control.faction_registry.entries:
			var entry: Dictionary = slot.control.faction_registry.entries[key]
			if not RegionFactionQuery.is_bandit(slot.control.faction_registry, int(key)): continue
			var table := RegionFactionQuery.bandit_of(slot.control.faction_registry, int(key))
			bands.append("%s:%s heat=%d hoard=%s fallen=%d" % [str(key), str(entry.status), int(table.get("heat", 0)), JSON.stringify(table.get("hoard", {})), int(table.get("fallen", 0))])
		var log := RegionBattleLog.table(slot.control.faction_registry)
		print("RAID_30DAY day=%d real_s=%d bands=[%s] parties=%d bound=%d battles=%d raids_open=%s" % [day - first_day, (Time.get_ticks_msec() - started_ms) / 1000, ", ".join(bands), slot.region_registry().get("parties", {}).size(), slot._region_original_labs.size(), log.records.size(), str(slot.get_meta(&"bandit_raids_open", {}))])
		var formula: Dictionary = slot.get_meta(&"bandit_formula_last", {})
		if not formula.get("raids", []).is_empty() or not formula.get("mustered", []).is_empty():
			print("RAID_30DAY FORMULA ", JSON.stringify(formula).left(600))
			for raid: Dictionary in formula.get("raids", []):
				formula_raids += 1
				if bool(raid.get("won", false)): formula_wins += 1
			musters += formula.get("mustered", []).size()
		if slot.has_meta(&"bandit_formula_refused"):
			print("RAID_30DAY REFUSED ", JSON.stringify(slot.get_meta(&"bandit_formula_refused")).left(300))
			slot.remove_meta(&"bandit_formula_refused")
		if slot.has_meta(&"bandit_raid_outcome"):
			print("RAID_30DAY LIVE_OUTCOME ", JSON.stringify(slot.get_meta(&"bandit_raid_outcome")).left(300))
			slot.remove_meta(&"bandit_raid_outcome")
		if slot.has_meta(&"bandit_raid_home"):
			print("RAID_30DAY LIVE_HOME ", JSON.stringify(slot.get_meta(&"bandit_raid_home")).left(300))
			slot.remove_meta(&"bandit_raid_home")
		print("RAID_30DAY JOURNAL rows=%d idle_released=%s" % [slot.control.get("fire_clock", {}).get("journal", []).size(), JSON.stringify(lab.get_meta(&"idle_release_last", {})).left(160)])
		if day - first_day >= _days(): break
		# The canonical verifier allows 3600 seconds: what was seen by then is the observation.
		if Time.get_ticks_msec() - boot_ms > 3200000: break
	var band_parties := 0
	for token: Variant in parties_seen:
		if RegionFactionQuery.is_bandit(slot.control.faction_registry, int(parties_seen[token])): band_parties += 1
	var records := RegionBattleLog.table(slot.control.faction_registry)
	var deaths := 0
	var downs := 0
	for battle: Dictionary in records.records:
		for side: Variant in battle.sides:
			deaths += int(battle.sides[side].deaths)
			downs += int(battle.sides[side].kos)
	print("RAID_30DAY SUMMARY formula_raids=%d won=%d musters=%d days=%d bands_on_the_map=%d battles=%d deaths=%d knockouts=%d bound_sites=%d" % [formula_raids, formula_wins, musters, last_day - first_day, band_parties, records.records.size(), deaths, downs, slot._region_original_labs.size()])
	for battle: Dictionary in records.records: print("RAID_30DAY BATTLE ", JSON.stringify(battle).left(500))
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("RAID_30DAY_DONE")
	quit(0)
