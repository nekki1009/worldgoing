extends SceneTree
## 土匪 B4e (bandit spec §4 C/D/E): unaffiliated people gather into a band. A world opens with a founded faction (the
## player captains his cadres). Four cadres leave as neutral loners (one a civilian); the player's team stays. Checks:
## - the watch takes the three armed loners (not the civilian, not the player's team) on the first day; the section
##   passes the save rules and malformed sections are refused;
## - on day 6 nothing forms; on day 7 the three found one band (origin refugee, lair here) in one team, chief = the
##   highest prestige, with a notice; the watch is cleared;
## - the Site saves and the native blob reloads.
## Output: SITE_BANDIT_DRIFTERS_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Drifters = preload("res://scripts/terrain_lab/site_bandit_drifters.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_DRIFTERS_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_DRIFTERS OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _blob_loads(lab: TerrainLab) -> bool:
	var native_save: Dictionary = lab.crowd_site.capture_save(true)
	if not native_save.get("ok", false): return false
	var native: Object = ClassDB.instantiate("ArmyCrowd")
	native.call("setup", 1, int(lab.terrain.seed_value))
	return bool(native.call("load_state", Marshalls.base64_to_raw(str(native_save.section.get("blob", "")))))

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "流寇世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var player := int(lab.controlled_person_id())
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 4, "the player has four cadres", cadres): return
	var loners: Array[int] = cadres.slice(0, 3)
	var civilian := cadres[3]
	for person: int in cadres.slice(0, 4):
		if not _check(lab.crowd_site.detach_to_new_team(person, RegionFactionQuery.NEUTRAL_FACTION_ID).ok, "#%d leaves as a neutral loner" % person): return
	if not _check(lab.crowd_site.native_set_military_role(civilian, "civilian").ok, "one loner is a civilian"): return
	controller.adjust_reputation(loners[1], 30.0, 0.0)
	var expected_chief := loners[1]

	var first: Dictionary = Drifters.day(controller, 10)
	var watch: Dictionary = lab.terrain.site.get(Drifters.SECTION, {})
	if not _check(int(first.watched) == 3 and watch.size() == 3 and not watch.has(str(civilian)) and not watch.has(str(player)) and int(watch[str(loners[0])]) == 10, "the watch takes the three armed loners", watch): return
	if not _check(Drifters.validate(lab.terrain.site).ok, "the section passes the save rules"): return
	for bad: Variant in [[], {"x": 1}, {"5": -1}, {"5": 1.5}]:
		if not _check(not Drifters.validate({Drifters.SECTION: bad}).ok, "a malformed section is refused", bad): return
	var early: Dictionary = Drifters.day(controller, 16)
	if not _check(early.formed.is_empty() and lab.terrain.site.has(Drifters.SECTION), "day 6: nothing forms yet", early): return
	var bands_before: int = slot.control.faction_registry.entries.size()
	var formed: Dictionary = {}
	for attempt: int in range(600):
		formed = Drifters.day(controller, 17)
		if not formed.formed.is_empty() or str(formed.code) != "NOT_READY": break
		if not _check(slot.control.faction_registry.entries.size() == bands_before, "a loner not ready yet founds nothing") : return
		await process_frame
	if not _check(not formed.formed.is_empty(), "day 7: they found a band", [formed, loners.map(func(p: int) -> Array:
		var t: Dictionary = lab.crowd_site.combat_target(p)
		return [p, t.get("cell"), lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[p])).get("state", -1)])]): return
	var band := int(formed.formed.band)
	var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	if not _check(RegionFactionQuery.is_bandit(slot.control.faction_registry, band) and str(table.get("origin", "")) == "refugee" and str(table.lair.site_id) == str(lab.terrain.site.id), "a refugee band with its lair here", table): return
	if not _check(int(formed.formed.chief) == expected_chief, "the highest prestige is chief", formed.formed): return
	var team: Dictionary = _team_of(lab, expected_chief)
	if not _check(int(team.faction) == band and team.person_ids.size() == 3 and loners.all(func(p: int) -> bool: return team.person_ids.has(p)) and int(controller.team_captain_of_team(int(team.team_id))) == expected_chief, "one team of three under the chief", team): return
	if not _check(not lab.terrain.site.has(Drifters.SECTION) and int(_team_of(lab, civilian).faction) == RegionFactionQuery.NEUTRAL_FACTION_ID, "the watch is cleared; the civilian stays neutral"): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []):
		if str(notice).contains("落草成伙"): noticed = true
	if not _check(noticed, "a notice tells of the band"): return
	var saved: Dictionary = controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
	if not _check(saved.ok and _blob_loads(lab) and lab.crowd_site.crowd.validate(), "the Site saves and the native blob reloads", saved): return
	_finished = true
	print("SITE_BANDIT_DRIFTERS_PASS: ", checks, " checks; unaffiliated loners gather into a band")
	quit(0)
