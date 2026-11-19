extends SceneTree
## 土匪 B4 source C (v2 plan §10.1–10.2 退隊): a member whose leave intent stands leaves his team. A world opens with a
## founded faction (the player captains his cadres). Checks:
## - nobody leaves without an intent; the controlled person never leaves, even with one;
## - a plain member (two cadres stand apart; the second is not a post holder) with a standing intent leaves that day:
##   he stands alone as a neutral person,
##   his nation membership untouched, with a notice; the team keeps its captain;
## - he is now a drifter the bandit watch takes in (SiteBanditDrifters).
## Output: SITE_DESERTION_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Desertion = preload("res://scripts/terrain_lab/site_desertion.gd")
const Drifters = preload("res://scripts/terrain_lab/site_bandit_drifters.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_DESERTION_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_DESERTION OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _intent(controller: SiteController, identity: int, ref: Dictionary) -> void:
	var entry: Dictionary = SiteSocial.relation(SiteSocial.state_of(controller.person_actions._person(identity, false).body), ref)
	entry["G"] = 90
	entry["intent"] = true

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "離隊世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var team: Dictionary = _team_of(lab, player)
	var size_before: int = team.person_ids.size()
	var cadres: Array[int] = []
	for person: Variant in team.person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 2, "the player has cadres", cadres): return
	var ref := SiteSocial.team_ref(str(lab.terrain.site.id), int(team.team_id))
	var quiet: Dictionary = Desertion.day(controller)
	if not _check(quiet.left.is_empty() and _team_of(lab, player).person_ids.size() == size_before, "without an intent nobody leaves", quiet): return
	_intent(controller, player, ref)
	if not _check(Desertion.day(controller).left.is_empty() and _team_of(lab, player).person_ids.has(player), "the controlled person never leaves"): return

	# The player's cadres hold team posts (a post holder never just walks off): two cadres stand apart, the first as
	# captain, the second a plain member of that team.
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], int(team.faction))
	if not _check(apart.ok and lab.crowd_site.join_team(cadres[1], int(apart.team_id)).ok, "two cadres stand apart, the second a plain member", apart): return
	for _frame: int in range(10): await process_frame
	team = _team_of(lab, player)
	size_before = team.person_ids.size()
	var leaver := cadres[1]
	_intent(controller, leaver, SiteSocial.team_ref(str(lab.terrain.site.id), int(apart.team_id)))
	var nations_before := JSON.stringify(lab.terrain.site.get("equipment_nations", {}))
	var notices_before: int = lab.terrain.site.get("notices", []).size()
	var gone: Dictionary = {}
	for _frame: int in range(600):
		gone = Desertion.day(controller)
		if not gone.left.is_empty(): break
		await process_frame
	if not _check(gone.left.size() == 1 and int(gone.left[0].id) == leaver, "the cadre with an intent leaves", gone): return
	var alone: Dictionary = _team_of(lab, leaver)
	if not _check(alone.person_ids.size() == 1 and int(alone.faction) == RegionFactionQuery.NEUTRAL_FACTION_ID and _team_of(lab, cadres[0]).person_ids.size() == 1 and _team_of(lab, player).person_ids.size() == size_before, "he stands alone as a neutral person; the team keeps the others", alone): return
	if not _check(JSON.stringify(lab.terrain.site.get("equipment_nations", {})) == nations_before, "his nation membership is untouched"): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []).slice(notices_before):
		if str(notice).contains("離開所屬隊伍"): noticed = true
	if not _check(noticed, "a notice tells of it"): return
	var watched: Dictionary = Drifters.day(controller, 50)
	if not _check(lab.terrain.site.get(Drifters.SECTION, {}).has(str(leaver)), "the bandit watch takes him in as a drifter", watched): return
	lab.terrain.site.erase(Drifters.SECTION)
	_finished = true
	print("SITE_DESERTION_PASS: ", checks, " checks; a member with a standing intent leaves his team")
	quit(0)
