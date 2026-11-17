extends SceneTree
## 平民 C3c on a crowd Site: drafted residents join the defenders' team and go back on release. A world opens with a
## founded faction (the player captains his cadres). Two cadres stand apart as the residents' team (the first is its
## captain), one cadre stands apart as an armed neutral (the danger). A test-only settlement stand-in (never saved)
## makes the player its head. Checks:
## - the player drafts: both residents are soldiers; the one who is not his own team's captain leaves the residents'
##   team for the player's (the defenders') team; the record keeps both team ids and passes the save rules;
## - with the danger gone the player releases them: civilians again, back in the residents' team, the record cleared.
## Output: SITE_MILITIA_CROWD_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Militia = preload("res://scripts/terrain_lab/site_militia.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_MILITIA_CROWD_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_MILITIA_CROWD OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _role(controller: SiteController, identity: int) -> String:
	return Militia._role(controller.person_actions._person(identity, false))

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "鄉勇群眾世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var defenders: Dictionary = _team_of(lab, player)
	var own := int(defenders.faction)
	var cadres: Array[int] = []
	for person: Variant in defenders.person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 3, "the player has three cadres", cadres): return
	var first := cadres[0]
	var second := cadres[1]
	var raider := cadres[2]
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(first, own)
	if not _check(apart.ok and lab.crowd_site.join_team(second, int(apart.team_id)).get("code", "") == "WHOLE_TEAM", "the first resident stands apart (a member cannot join without leaving first)", apart): return
	var second_apart: Dictionary = lab.crowd_site.detach_to_new_team(second, own)
	if not _check(second_apart.ok and lab.crowd_site.join_team(second, int(apart.team_id)).ok, "the second resident joins him: the residents' team", second_apart): return
	var home := int(apart.team_id)
	if not _check(lab.crowd_site.native_set_military_role(first, "civilian").ok and lab.crowd_site.native_set_military_role(second, "civilian").ok, "both are civilians"): return
	if not _check(lab.crowd_site.detach_to_new_team(raider, RegionFactionQuery.NEUTRAL_FACTION_ID).ok, "an armed neutral stands on the Site"): return
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "militia_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["housing"] = {str(first): {"version": 1, "house_id": "h1", "cell": 0}, str(second): {"version": 1, "house_id": "h1", "cell": 1}}

	var drafted: Dictionary = Militia.draft(lab, player)
	if not _check(drafted.ok and _role(controller, first) == "soldier" and _role(controller, second) == "soldier", "the player drafts both residents", drafted): return
	var record: Dictionary = lab.terrain.site.get(Militia.SECTION, {})
	if not _check(int(_team_of(lab, second).team_id) == int(defenders.team_id) and int(_team_of(lab, first).team_id) == home, "the drafted member joins the defenders; the residents' own captain stays", [_team_of(lab, second), _team_of(lab, first)]): return
	if not _check(int(record.get("home", -1)) == home and int(record.get("into", -1)) == int(defenders.team_id) and Militia.validate(lab.terrain.site).ok, "the record keeps both teams and passes the save rules", record): return

	if not _check(lab.crowd_site.native_set_military_role(raider, "civilian").ok, "the danger passes"): return
	var released: Dictionary = Militia.release(lab, player)
	if not _check(released.ok and _role(controller, first) == "civilian" and _role(controller, second) == "civilian" and int(_team_of(lab, second).team_id) == home and not lab.terrain.site.has(Militia.SECTION), "released: civilians again, back in the residents' team", [released, _team_of(lab, second)]): return
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("housing")
	_finished = true
	print("SITE_MILITIA_CROWD_PASS: ", checks, " checks; drafted residents join the defenders and go back")
	quit(0)
