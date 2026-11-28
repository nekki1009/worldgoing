extends SceneTree
## Bands founded on a Site the player does not stand in (2026-11-25): only the active Site's controller may save the
## registry, so the people of a bound cold Site were refused and stayed adrift. A small generated scenario world (6
## settlements, 3 bands, 1 town); a village is bound as a cold owner with the world standing still. Checks, there:
## - three armed loners found a band after the wait (SiteBanditDrifters.day): saved, lair there, one team, at war with the village;
## - three survivors of a rout found a band (SiteBanditRout.form);
## - a fence sale's heat is saved (SiteBanditFence.flush);
## - the world's diplomacy is settled by the active Site alone;
## - the world goes on an hour, saves, and the saved registry and the village's file hold all of it.
## Output: REGION_COLD_BAND_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Drifters = preload("res://scripts/terrain_lab/site_bandit_drifters.gd")
const Rout = preload("res://scripts/terrain_lab/site_bandit_rout.gd")
const Fence = preload("res://scripts/terrain_lab/site_bandit_fence.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _fail("1500-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_COLD_BAND_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_COLD_BAND OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _bind(id: String) -> Dictionary:
	lab.set_process(false)
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	return bound

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _team_of(field: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in field.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## The armed people of `faction` who are not captains, sorted.
func _soldiers(field: TerrainLab, faction: int) -> Array[int]:
	var found: Array[int] = []
	for team: Dictionary in field.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != faction or team.get("person_ids", []).size() < 2: continue
		var captain := int(field.site_controller.team_captain_of_team(int(team.team_id)))
		for person: Variant in team.get("person_ids", []):
			if int(person) == captain: continue
			var body: Dictionary = field.site_controller.person_actions._person(int(person), false)
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0 or SiteOffices.body_military_role(body.get("body")) == "civilian": continue
			found.append(int(person))
	found.sort()
	return found

func _band_saved(band: int, lair: String, origin: String) -> bool:
	var registry: Dictionary = slot.control.faction_registry
	if not RegionFactionQuery.is_bandit(registry, band): return false
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	return str(table.get("origin", "")) == origin and table.get("lair") is Dictionary and str(table.lair.site_id) == lair

func _run() -> void:
	var folder := "user://cold_band_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "冷站成伙", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 900000
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
	var here := str(lab.terrain.site.id)
	# Every band lies low: nothing else is bound or raided meanwhile.
	for key: Variant in slot.control.faction_registry.entries:
		var lying := int(slot.control.faction_registry.entries[key].faction_id)
		if not RegionFactionQuery.is_bandit(slot.control.faction_registry, lying): continue
		var hot: Dictionary = Bandit.set_heat(slot.control.faction_registry, lying, 80, float(slot.control.logical_game_seconds))
		if not _ok(hot.ok and lab.site_controller._commit_diplomacy(hot, "").ok, "band %d lies low" % lying, hot): return
	# The settlement with the most soldiers, but not a town's garrison.
	var village := ""
	var most := 0
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2 or "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]] == here: continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var armed := 0
		for army: Variant in loaded.data.site.get("armies", []):
			if not army is Dictionary: continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary and str(unit.get("military_role", "")) != "civilian": armed += 1
		if armed > most:
			most = armed
			village = "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
	if not _ok(not village.is_empty() and most >= 8, "a settlement with soldiers: %s (%d)" % [village, most]): return
	var bound: Dictionary = await _bind(village)
	if not _ok(bound.get("ok", false), "it is bound as a cold owner", bound): return
	var field: TerrainLab = slot._region_original_labs[village]
	var cold: SiteController = field.site_controller
	var owner := int(field.terrain.site.settlement.owner_faction)
	var soldiers := _soldiers(field, owner)
	var roles := {}
	for soldier_team: Dictionary in field.crowd_site.teams: roles[int(soldier_team.team_id)] = [int(soldier_team.get("faction", -1)), soldier_team.get("person_ids", []).map(func(p: Variant) -> String: return SiteOffices.body_military_role(cold.person_actions._person(int(p), false).get("body")))]
	print("REGION_COLD_BAND TEAMS ", JSON.stringify(roles).left(900))
	if not _ok(soldiers.size() >= 6, "six soldiers who are no captains", soldiers.size()): return
	if not _ok(cold.registry_saver() == lab.site_controller and lab.site_controller.registry_saver() == lab.site_controller, "the active Site's controller saves for both"): return
	if not _ok(cold.npc_diplomacy_day().is_empty() and cold.settle_diplomacy().is_empty(), "a cold Site settles no diplomacy"): return
	if not _ok(not cold._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "").get("ok", false), "a cold Site's own save is refused"): return

	# Drifters.
	lab.set_process(false)
	var loners: Array[int] = soldiers.slice(0, 3)
	for person: int in loners:
		for attempt: int in range(40):
			if field.crowd_site._split_exit_ready(field.crowd_site.person_owner(person), int(field.crowd_site._index_by_id.get(person, -1))): break
			if not await _frame(): return
		var left: Dictionary = field.crowd_site.detach_to_new_team(person, RegionFactionQuery.NEUTRAL_FACTION_ID)
		if not _ok(left.ok, "#%d leaves as a neutral loner" % person, left): return
	for person: int in loners: field.terrain.site.get("housing", {}).erase(str(person))
	var today := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	var watched: Dictionary = Drifters.day(cold, today)
	if not _ok(int(watched.watched) == 3 and watched.formed.is_empty(), "the watch takes the three", watched): return
	var bands_before: int = slot.control.faction_registry.entries.size()
	var formed: Dictionary = {}
	for attempt: int in range(300):
		formed = Drifters.day(cold, today + Bandit.FORM_WAIT_DAYS)
		if not formed.formed.is_empty() or str(formed.code) != "NOT_READY": break
		if not await _frame(): return
	if not _ok(not formed.formed.is_empty(), "after the wait they found a band", [formed, watched]): return
	var drift_band := int(formed.formed.band)
	var team := _team_of(field, int(formed.formed.chief))
	if not _ok(_band_saved(drift_band, village, "refugee") and slot.control.faction_registry.entries.size() == bands_before + 1, "band %d is saved, its lair is there" % drift_band): return
	if not _ok(int(team.get("faction", -1)) == drift_band and team.person_ids.size() == 3 and loners.all(func(p: int) -> bool: return team.person_ids.has(p)), "the three stand in one team of it", team): return
	var village_team := {}
	for other: Dictionary in field.crowd_site.teams:
		if not bool(other.get("departed", false)) and int(other.get("faction", -1)) == owner and not other.get("person_ids", []).is_empty(): village_team = other
	var hostile: bool = not village_team.is_empty() and RegionDiplomacy.hostile(slot.control.faction_registry, drift_band, owner, float(slot.control.logical_game_seconds))
	if not _ok(hostile and field.crowd_site.native_faction_of(team) != field.crowd_site.native_faction_of(village_team), "they and the village are enemies in slots of their own"): return

	# A rout.
	var routed: Array = soldiers.slice(3, 6)
	for person: int in routed:
		for attempt: int in range(40):
			if field.crowd_site._split_exit_ready(field.crowd_site.person_owner(person), int(field.crowd_site._index_by_id.get(person, -1))): break
			if not await _frame(): return
	var rout: Dictionary = Rout.form(cold, int(routed[0]), routed)
	if not _ok(rout.ok, "three survivors of a rout found a band", rout): return
	var rout_band := int(rout.band)
	var rout_team := _team_of(field, int(routed[0]))
	if not _ok(_band_saved(rout_band, village, "rout") and int(rout_team.get("faction", -1)) == rout_band and rout_team.person_ids.size() == 3, "band %d is saved, the three stand in one team" % rout_band, rout_team): return

	# A fence sale's heat.
	var heat := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, rout_band).get("heat", 0))
	Fence.queue_heat(cold, rout_band)
	var flushed: Dictionary = Fence.flush(cold)
	if not _ok(flushed.get("ok", false) and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, rout_band).get("heat", 0)) == Bandit.heat_after(heat, "fence") and not cold.has_meta(&"fence_heat_due"), "a fence sale's heat is saved", flushed): return

	# It goes on, and what is saved holds it.
	lab.set_process(true)
	lab.simulation_speed = 16.0
	var from := float(slot.control.logical_game_seconds)
	for frame: int in range(2400):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - from > 3600.0: break
	if not _ok(float(slot.control.logical_game_seconds) - from > 3600.0, "an hour goes on"): return
	var saved: Dictionary = {}
	for attempt: int in range(200):
		saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if saved.get("ok", false): break
		if not await _frame(): return
	if not _ok(saved.get("ok", false), "the world saves", saved): return
	var read: Dictionary = slot.region_commit_control(int(slot._marker.generation))
	var registry: Variant = read.get("control", {}).get("faction_registry", {})
	if not _ok(read.get("ok", false) and registry is Dictionary and RegionFactionQuery.is_bandit(registry, drift_band) and RegionFactionQuery.is_bandit(registry, rout_band), "the saved registry holds both bands", read.get("code", read.keys())): return
	var parts: PackedStringArray = village.split(":")
	var key := "%s:%s" % [parts[parts.size() - 2], parts[parts.size() - 1]]
	var file: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[key].path)), Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1])))
	var in_file := {}
	if file.ok:
		for army: Variant in file.data.site.get("armies", []):
			if not army is Dictionary: continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary and int(unit.get("person_id", -1)) > 0: in_file[int(unit.person_id)] = int(army.get("faction_id", -1))
	var as_expected := true
	for person: int in loners: as_expected = as_expected and (not in_file.has(person) or int(in_file[person]) == drift_band)
	for person: Variant in routed: as_expected = as_expected and (not in_file.has(int(person)) or int(in_file[int(person)]) == rout_band)
	print("REGION_COLD_BAND FILE ", JSON.stringify(in_file).left(400))
	if not _ok(file.ok and as_expected, "the village's file holds them under their new bands", in_file): return
	# Nobody looks at it: its people have no kits (2026-11-25, CrowdSite._undrawn). A Lab that becomes visible gets them at its first frame.
	var unseen: Variant = field.crowd_site
	if not _ok(unseen._kits_skipped and unseen.view == null and unseen.render_kit_ids().size() == int(unseen.crowd.soldier_count()) and not Array(unseen.render_kit_ids()).any(func(kit: int) -> bool: return kit >= 0), "the unseen Site's people have no kits", Array(unseen.render_kit_ids())): return
	field.restore_only = false
	unseen.render(1.0 / 60.0)
	var drawn: Array = Array(unseen.render_kit_ids())
	field.restore_only = true
	if not _ok(not unseen._kits_skipped and unseen.view != null and drawn.any(func(kit: int) -> bool: return kit >= 0), "seen, they have", drawn): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_COLD_BAND_PASS: ", checks, " checks")
	quit(0)
