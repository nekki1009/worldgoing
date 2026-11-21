extends SceneTree
## 土匪 B4d-3b (bandit spec §5.1, §5.2): after a raid. A 落草 world opens (the player chiefs a band of himself and five
## cadres); one cadre founds 乙國 (none of its people stand here); a cadre takes the chief's seat and leads two cadres in
## a team of his own; the band's lair moves to a neighbouring Site, so its teams here are away. A test-only stand-in
## settlement of 乙國 (never saved: erased before anything saves) stands here. Checks:
## - plunder takes CARRY per standing bandit, food first, then the rest by name;
## - while 乙國 still has someone standing nothing is taken; when the battle closes with 乙國 down and the band
##   standing, the band's lair hoard gains the plunder and the Site's stock loses it, with a notice;
## - the band's next day sends the chief's team home toward the lair (the player's team is never sent).
## Output: SITE_BANDIT_AFTERMATH_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_BANDIT_AFTERMATH_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_AFTERMATH OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	# Pure plunder first.
	var taken := Aftermath.plunder({"wood": 50, "grain": 30, "fish": 5, "cloth": 3}, 3)
	if not _check(taken == {"grain": 30, "fish": 5, "cloth": 3, "wood": 22}, "plunder takes 20 per bandit, food first, then by name", taken): return
	if not _check(Aftermath.plunder({"grain": 30}, 0).is_empty(), "nobody standing takes nothing"): return

	var requested: bool = RegionEntry.request_new_world(START, {}, "劫後世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"})
	if not _check(requested, "a 落草 world is requested", RegionEntry.menu_message): return
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
	var band := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 5, "the player's band has five cadres", cadres): return
	var now := float(slot.control.logical_game_seconds)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[4]), "founded_at": now})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	# 乙國's people are not on this Site (a bandit fights anyone in sight; the standing counts are given to the judge).
	var chief := cadres[0]
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(chief, band)
	if not _check(apart.ok, "the chief stands apart in a team of the band", apart): return
	var team_id := int(apart.team_id)
	for person: int in cadres.slice(1, 3):
		if not _check(lab.crowd_site.join_team(person, team_id).ok, "#%d joins the chief" % person): return
	var succeeded: Dictionary = Bandit.succeed(slot.control.faction_registry, band, JoinFaction._world_ref(controller, chief), now)
	if not _check(succeeded.ok and controller._commit_diplomacy(succeeded, "").ok, "the cadre is the band's chief now", succeeded): return
	var raiding: Dictionary = Bandit._with_table(slot.control.faction_registry, band, func(table: Dictionary) -> void: table.raid_ai = true, now)
	if not _check(raiding.ok and controller._commit_diplomacy(raiding, "").ok, "the band's raid AI is on", raiding): return
	var here: Dictionary = slot._coordinate(lab.terrain)
	var lair_site := ""
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var next: Vector2i = here.site + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y)
		if summary.get("ok", false) and str(summary.get("status", "")) in ["land", "mixed"]:
			lair_site = Grid.site_id(str(slot.pin.atlas_id), next)
			break
	var moved: Dictionary = Bandit.move_lair(slot.control.faction_registry, band, lair_site, Vector2i(64, 64), now)
	if not _check(not lair_site.is_empty() and moved.ok and controller._commit_diplomacy(moved, "").ok, "the lair moves to a neighbouring Site", moved): return
	var away: Array = Aftermath.away_teams(controller, band)
	if not _check(away.has(team_id), "the band's teams here are away from the lair", away): return

	# The stand-in settlement exists only while nothing saves.
	var stand_in := {"version": 1, "settlement_id": "aftermath_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": lawful,
		"offices": SiteOffices.default_offices("settlement", cadres[4], false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["settlement"] = stand_in
	if not _check(Aftermath.after_battle(controller, {band: 5, lawful: 1}).is_empty(), "while a defender stands nothing is taken"): return
	lab.terrain.site.erase("settlement")
	if not lab.terrain.site.get("inventory") is Dictionary: lab.terrain.site["inventory"] = {}
	var inventory: Dictionary = lab.terrain.site.inventory
	var grain_before := int(inventory.get("grain", 0))
	inventory["grain"] = grain_before + 200
	var hoard_before := int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).get("grain", 0))
	var notices_before: int = lab.terrain.site.get("notices", []).size()
	# The settlement's record is read when the battle closes; it is gone again before the hoard and Site save.
	var plundered := _after_battle_with_stand_in(controller, stand_in, {band: 3, lawful: 0})
	if not _check(plundered.get("ok", false) and int(plundered.band) == band and int(plundered.taken.get("grain", 0)) == 60, "with 乙國 down the band takes 60 grain", plundered): return
	if not _check(int(lab.terrain.site.inventory.get("grain", 0)) == grain_before + 140 and int(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).hoard.grain) == hoard_before + 60, "the stock loses it and the lair hoard gains it"): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []).slice(notices_before):
		if str(notice).contains("劫走"): noticed = true
	if not _check(noticed, "a notice tells of the plunder"): return

	for _frame: int in range(900):
		var ready := true
		for person: Variant in _team_of(lab, chief).person_ids:
			var owner: Variant = lab.crowd_site.person_owner(int(person))
			if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[int(person)])): ready = false
		if ready: break
		await process_frame
	for _frame: int in range(10): await process_frame # the native seats the chief as captain on its next step
	var day: Dictionary = BanditDay.run(controller, 41)
	var row: Dictionary = {}
	for action: Dictionary in day.actions:
		if int(action.band) == band: row = action
	if not _check(str(row.get("action", "")) == "go_home" and row.ok and int(row.team) == team_id and _team_of(lab, chief).is_empty(), "the chief's team leaves for the lair", day): return
	_finished = true
	print("SITE_BANDIT_AFTERMATH_PASS: ", checks, " checks; a band plunders and goes home")
	quit(0)

## The verdict reads the stand-in settlement; it is gone before the hoard and the Site save.
func _after_battle_with_stand_in(controller: SiteController, stand_in: Dictionary, standing: Dictionary) -> Dictionary:
	var data: TerrainData = controller.lab.terrain
	data.site["settlement"] = stand_in
	var verdict := Aftermath.judge(controller, standing)
	data.site.erase("settlement")
	return Aftermath.apply(controller, verdict) if not verdict.is_empty() else {}
