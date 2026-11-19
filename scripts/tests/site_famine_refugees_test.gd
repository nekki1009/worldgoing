extends SceneTree
## 土匪 B4 source E: famine makes refugees. A world opens with a founded faction (the player captains his cadres); four
## cadres stand apart as one team (the first its captain) with its own supply; its cohorts' hunger is set to make all
## four starve. Checks:
## - the first famine day starts the watch and nobody leaves; day 9 of it still nobody;
## - day 10: a tenth (one) of the starving leaves, never the captain, standing alone as a neutral person, with a notice;
##   the drifter watch takes him in;
## - a fed day clears the team's entry; the section passes the save rules and malformed ones are refused.
## Output: SITE_FAMINE_REFUGEES_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Famine = preload("res://scripts/terrain_lab/site_famine_refugees.gd")
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
	printerr("SITE_FAMINE_REFUGEES_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FAMINE_REFUGEES OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "饑荒世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var player := int(lab.controlled_person_id())
	var faction := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 4, "the player has four cadres", cadres): return
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], faction)
	if not _check(apart.ok, "the first cadre stands apart as a captain", apart): return
	var team_id := int(apart.team_id)
	for person: int in cadres.slice(1, 4):
		if not _check(lab.crowd_site.join_team(person, team_id).ok, "#%d joins him" % person): return
	for _frame: int in range(10): await process_frame
	var members: Array = cadres.slice(0, 4)
	var supply: Dictionary = controller._enable_team_supply(lab.crowd_site.native_owner(team_id))
	if not _check(not supply.is_empty(), "the team has its own supply", supply.keys()): return
	var set_hunger := func(hours: float) -> void:
		for cohort: Dictionary in lab.terrain.site.team_supply[str(team_id)].sustain.cohorts: cohort["hunger"] = hours
	set_hunger.call(20.0)
	if not _check(Famine.starving(lab, team_id) == members, "all four starve", Famine.starving(lab, team_id)): return

	var first := Famine.day(controller, 100)
	if not _check(first.famine.has(team_id) and first.left.is_empty() and int(lab.terrain.site.get(Famine.SECTION, {}).get(str(team_id), -1)) == 100, "the first famine day starts the watch", first): return
	if not _check(Famine.day(controller, 109).left.is_empty(), "day 9 of famine: nobody leaves yet"): return
	var notices_before: int = lab.terrain.site.get("notices", []).size()
	var tenth: Dictionary = {}
	for _frame: int in range(600):
		tenth = Famine.day(controller, 110)
		if not tenth.left.is_empty(): break
		await process_frame
	if not _check(tenth.left.size() == 1 and int(tenth.left[0].id) != cadres[0], "day 10: one starving member (not the captain) leaves", tenth): return
	var refugee := int(tenth.left[0].id)
	var alone: Dictionary = _team_of(lab, refugee)
	if not _check(alone.person_ids.size() == 1 and int(alone.faction) == RegionFactionQuery.NEUTRAL_FACTION_ID, "he stands alone as a neutral person", alone): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []).slice(notices_before):
		if str(notice).contains("饑荒"): noticed = true
	if not _check(noticed, "a notice tells of the famine"): return
	Drifters.day(controller, 110)
	if not _check(lab.terrain.site.get(Drifters.SECTION, {}).has(str(refugee)), "the drifter watch takes him in"): return
	if not _check(Famine.validate(lab.terrain.site).ok, "the section passes the save rules"): return
	for bad: Variant in [[], {"x": 1}, {"5": -1}, {"5": 2.5}]:
		if not _check(not Famine.validate({Famine.SECTION: bad}).ok, "a malformed section is refused", bad): return
	set_hunger.call(0.0)
	Famine.day(controller, 111)
	if not _check(not lab.terrain.site.has(Famine.SECTION), "a fed day clears the watch"): return
	lab.terrain.site.erase(Drifters.SECTION)
	_finished = true
	print("SITE_FAMINE_REFUGEES_PASS: ", checks, " checks; famine makes refugees")
	quit(0)
