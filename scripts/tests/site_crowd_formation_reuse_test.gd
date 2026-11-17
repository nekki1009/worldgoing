extends SceneTree
## Native crowd: a team everyone left gives its formation to the next new team (CrowdSite.native_add_team reuses it through
## the native site_formation_reuse). A world opens with a founded faction (the player captains his cadres). Checks:
## - a cadre leaving the player's team and coming back 30 times grows the native formation count by at most one;
## - the emptied team's record and roster are gone; the cadre's own one-person team is the reused formation;
## - the native state validates and the Site saves; the native blob reloads.
## Output: SITE_CROWD_FORMATION_REUSE_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_CROWD_FORMATION_REUSE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CROWD_FORMATION_REUSE OK ", checks, ": ", message)
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
	if not _check(RegionEntry.request_new_world(START, {}, "編組回收世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var home := int(_team_of(lab, player).team_id)
	var faction := int(_team_of(lab, player).faction)
	var cadre := -1
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player and cadre < 0: cadre = int(person)
	var before := int(lab.crowd_site.crowd.formation_count())
	var teams_before: int = lab.crowd_site.teams.size()
	for cycle: int in range(30):
		for _frame: int in range(600):
			var owner: Variant = lab.crowd_site.person_owner(cadre)
			if owner != null and lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[cadre])): break
			await process_frame
		var left: Dictionary = lab.crowd_site.detach_to_new_team(cadre, faction)
		if not _check(left.ok, "cycle %d: the cadre leaves" % cycle, left): return
		var back: Dictionary = lab.crowd_site.join_team(cadre, home)
		if not _check(back.ok, "cycle %d: the cadre comes back" % cycle, back): return
	var after := int(lab.crowd_site.crowd.formation_count())
	if not _check(after <= before + 1, "30 leave-and-return cycles grow the formations by at most one", [before, after]): return
	if not _check(lab.crowd_site.teams.size() <= teams_before + 1, "emptied team records do not pile up", [teams_before, lab.crowd_site.teams.size()]): return
	var empty_rosters := 0
	for roster: Dictionary in lab.crowd_site.rosters:
		if roster.get("units", []).is_empty(): empty_rosters += 1
	if not _check(empty_rosters <= 1, "at most the last emptied roster is kept", empty_rosters): return
	if not _check(lab.crowd_site.crowd.validate(), "the native state validates"): return
	var saved: Dictionary = controller._commit_diplomacy({"ok": true, "registry": controller.region_slot.control.faction_registry}, "")
	if not _check(saved.ok and _blob_loads(lab), "the Site saves and the native blob reloads", saved): return
	_finished = true
	print("SITE_CROWD_FORMATION_REUSE_PASS: ", checks, " checks; emptied formations serve new teams")
	quit(0)
