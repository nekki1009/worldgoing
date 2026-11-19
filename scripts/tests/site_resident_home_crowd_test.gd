extends SceneTree
## 平民 C1c on a crowd Site (reports/c1c-in-home-plan.md): a resident inside his house is natively absent with kind 5.
## Fixture as site_militia_crowd_test (two cadres as the residents' team, both civilians; an armed neutral). Checks:
## - the second resident enters: native absent [1, 5], not present natively, not drawn; the presence map says member and
##   not present; the roster row the save writes for him passes the save rules (Store._crowd_presence_matches);
## - a second enter, the controlled person and an unknown person are refused, changing nothing;
## - he leaves at his own cell and is on the field again;
## - inside again, a militia draft brings him out at his door as a soldier.
## Output: SITE_RESIDENT_HOME_CROWD_PASS on success; quit(1) on any failure or the deadline.

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
	printerr("SITE_RESIDENT_HOME_CROWD_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_HOME_CROWD OK ", checks, ": ", message)
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
	if not _check(apart.ok, "the first resident stands apart", apart): return
	var moved: Dictionary = lab.crowd_site.join_team(second, int(apart.team_id))
	if not _check(moved.ok and lab.crowd_site.join_team(player, int(apart.team_id)).get("code", "") == "CAPTAIN_REQUIRED", "the second resident moves straight across to him; a formal captain cannot", moved): return
	var home := int(apart.team_id)
	if not _check(lab.crowd_site.native_set_military_role(first, "civilian").ok and lab.crowd_site.native_set_military_role(second, "civilian").ok, "both are civilians"): return
	if not _check(lab.crowd_site.detach_to_new_team(raider, RegionFactionQuery.NEUTRAL_FACTION_ID).ok, "an armed neutral stands on the Site"): return
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "militia_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["housing"] = {str(first): {"version": 1, "house_id": "h1", "cell": 0}, str(second): {"version": 1, "house_id": "h1", "cell": 1}}

	var crowd: RefCounted = lab.crowd_site.crowd
	var index := int(lab.crowd_site._index_by_id[second])
	var before: Dictionary = lab.crowd_site.soldier_state(index)
	if not _check(lab.crowd_site.home_enter(second) and lab.crowd_site.is_at_home(second), "the resident goes inside his house"): return
	if not _check(Array(crowd.site_person_absent_state(index)) == [1.0, 5.0], "natively absent at home (kind 5), not on the field", Array(crowd.site_person_absent_state(index))): return
	var owner: Variant = lab.crowd_site._owner_by_id[second]
	var presence: Dictionary = owner.presence_state(index)
	if not _check(bool(presence.member) and not bool(presence.present) and not bool(presence.site_exited), "the roster keeps him as a member who is not present", presence): return
	var synced: Dictionary = lab.crowd_site.sync_to_site()
	if not _check(synced.get("ok", true), "the crowd syncs to the Site", synced): return
	var row := {}
	for roster: Dictionary in lab.terrain.site.armies:
		for unit: Dictionary in roster.get("units", []):
			if int(unit.get("person_id", -1)) == second: row = unit
	if not _check(not row.is_empty() and SiteStore._crowd_presence_matches(crowd, index, row), "his saved roster row passes the save rules", row): return
	var bytes: PackedByteArray = crowd.save_state()
	if not _check(not lab.crowd_site.home_enter(second) and not lab.crowd_site.home_enter(player) and not lab.crowd_site.home_enter(2147483000) and crowd.save_state() == bytes, "a second enter, the controlled person and an unknown person are refused, nothing changes"): return
	if not _check(lab.crowd_site.home_leave(second) and not lab.crowd_site.is_at_home(second) and Array(crowd.site_person_absent_state(index)) == [0.0, 0.0], "he comes out and is on the field again"): return
	var after: Dictionary = lab.crowd_site.soldier_state(index)
	if not _check(Vector2(float(after.px), float(after.py)).distance_to(Vector2(float(before.px), float(before.py))) < 1.5, "he comes out at his own door cell", [before, after]): return
	if not _check(not lab.crowd_site.home_leave(second), "leaving twice is refused"): return
	if not _check(lab.crowd_site.home_enter(second), "inside again"): return
	var drafted: Dictionary = Militia.draft(lab, player)
	if not _check(drafted.ok and _role(controller, second) == "soldier" and not lab.crowd_site.is_at_home(second) and Array(crowd.site_person_absent_state(index)) == [0.0, 0.0], "a militia draft brings him out at his door as a soldier", drafted): return
	if not _check(lab.crowd_site.native_set_military_role(raider, "civilian").ok and Militia.release(lab, player).ok, "released after the danger"): return
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("housing")
	_finished = true
	print("SITE_RESIDENT_HOME_CROWD_PASS: ", checks, " checks; at home = native absent kind 5, roster member not present, saved, refused twice, comes out at the door and for a draft")
	quit(0)
