extends SceneTree
## NPC rebellion (爵位規劃「叛離」 with 職位計畫 §8.4 預兆). The player founds 甲國 and makes a cadre of his own team a baron.
## Checks:
## - without a departure intent the NPC day does nothing;
## - an intent toward another team does not count;
## - with an intent toward his own team the baron declares himself independent once per game day: he is king of a new
##   rebel faction, leaves the player's team as captain of a one-person team of that faction, loses 30 credit, the player
##   keeps his team and his faction, and the two factions are hostile.
## Output: REGION_NPC_REBELLION_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
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
	printerr("REGION_NPC_REBELLION_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_NPC_REBELLION OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if team.get("person_ids", []).has(person) and not bool(team.get("departed", false)): return team
	return {}

func _intent(controller: SiteController, person: int, ref: Dictionary) -> bool:
	var body: Variant = controller.person_actions._person(person, false).get("body")
	if body == null: return false
	var entry: Dictionary = SiteSocial.relation(SiteSocial.state_of(body), ref)
	entry["G"] = 100
	entry["intent"] = true
	return true

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "NPC 叛離測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"})
	if not _check(requested, "a new world with a founded faction is requested", RegionEntry.menu_message): return
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
	var start_team: Dictionary = _team_of(lab, player)
	var mine := controller.diplomacy_head_faction()
	if not _check(mine >= 0 and mine == int(start_team.faction) and start_team.person_ids.size() == 1 + TerrainLab.INITIAL_CADRES, "the founder heads his faction and captains a team with cadres", [mine, start_team]): return
	var noble := -1
	for person: Variant in start_team.person_ids:
		if int(person) != player and noble < 0: noble = int(person)
	var player_ref: Variant = slot.peerage_person_ref(player)
	var noble_ref: Dictionary = JoinFaction._world_ref(controller, noble)
	if not _check(player_ref != null and not noble_ref.is_empty(), "both have world person refs"): return
	var granted: Dictionary = RegionPeerage.grant(slot.control.faction_registry, player_ref, noble_ref, "baron", [2], float(slot.control.logical_game_seconds))
	if not _check(controller._commit_peerage(granted, "男爵").ok and RegionPeerage.record_of(slot.control.faction_registry, noble_ref).get("rank") == "baron", "the king makes his cadre a baron"): return

	controller._npc_rebellion_day = -1
	if not _check(controller.npc_rebellion_day().is_empty(), "a baron without a departure intent stays"): return
	var site_id := str(lab.terrain.site.get("id", ""))
	if not _check(_intent(controller, noble, SiteSocial.team_ref(site_id, 999999)), "a departure intent toward another team is set"): return
	controller._npc_rebellion_day = -1
	if not _check(controller.npc_rebellion_day().is_empty() and not controller.rebellion_intent(noble, mine), "an intent toward another team does not count"): return
	var team_id := int(start_team.team_id)
	if not _check(_intent(controller, noble, SiteSocial.team_ref(site_id, team_id)), "a departure intent toward his own team is set"): return
	if not _check(controller.rebellion_intent(noble, mine), "the intent toward his own team counts"): return
	controller._npc_rebellion_day = -1
	var done: Dictionary = controller.npc_rebellion_day()
	if not _check(done.get("ok", false), "the NPC day lets the baron rebel", done): return
	if not _check(controller.npc_rebellion_day().is_empty(), "at most once per game day"): return
	var registry: Dictionary = slot.control.faction_registry
	var new_faction := int(done.faction_id)
	var record: Dictionary = RegionPeerage.record_of(registry, noble_ref)
	if not _check(new_faction != mine and record.get("rank") == "king" and record.get("liege_ref") == null and int(record.get("faction_id", -1)) == new_faction, "the baron is king of a new faction", record): return
	if not _check(registry.entries[str(new_faction)].kind == "rebel" and RegionPeerage.same_ref(registry.entries[str(new_faction)].leader_ref, noble_ref), "the new faction is a rebel faction led by him", registry.entries[str(new_faction)]): return
	var noble_team: Dictionary = _team_of(lab, noble)
	var noble_roster: Dictionary = lab.crowd_site.native_roster(int(noble_team.get("team_id", -1)))
	if not _check(int(noble_team.get("faction", -1)) == new_faction and int(noble_team.team_id) != team_id and noble_team.person_ids.size() == 1 and int(noble_roster.get("formal_commander", -1)) == 0, "he left the player's team as captain of his own team", noble_team): return
	var player_team: Dictionary = _team_of(lab, player)
	if not _check(int(player_team.team_id) == team_id and int(player_team.faction) == mine and not player_team.person_ids.has(noble), "the player keeps his team and faction"): return
	if not _check(RegionPeerage.record_of(registry, player_ref).get("rank") == "king" and int(RegionPeerage.record_of(registry, player_ref).faction_id) == mine, "the player is still king of his faction"): return
	if not _check(int(controller.reputation_of(noble).credit) == -3000, "independence costs him 30 credit", controller.reputation_of(noble)): return
	if not _check(RegionDiplomacy.hostile(registry, mine, new_faction, float(slot.control.logical_game_seconds)), "the two factions are hostile"): return
	_finished = true
	print("REGION_NPC_REBELLION_PASS: ", checks, " checks; intent gate, once a day, independence and the team move hold")
	quit(0)
