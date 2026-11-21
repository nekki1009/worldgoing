extends SceneTree
## Joining a faction in person (plan "勢力爵位與封地規劃", step 2). A new neutral world opens; one cadre leaves the
## player's team on the spot as the captain of his own one-person team of a newly founded faction whose king he is
## (this is the official the player meets). Another cadre gets an opposite personality so he will not follow. Checks:
## - a cadre detaches into his own one-person team in this Site (captain of it, posts vacated in the old team);
## - the preview names the official's decision and the cadre who would not follow, and changes nothing;
## - joining: the refusing cadre becomes the captain of his own one-person neutral team, the rest of the team is the
##   faction, the player swears fealty to the official (untitled, liege = official) and the Region checkpoint saves it;
## - a second join is refused (no longer neutral).
## Output: REGION_JOIN_FACTION_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_JOIN_FACTION_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_JOIN_FACTION OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if team.get("person_ids", []).has(person) and not bool(team.get("departed", false)): return team
	return {}

func _set_personality(lab: TerrainLab, person: int, value: int) -> bool:
	var target: Dictionary = lab._original_person_target(person)
	if target.is_empty() or int(target.get("unit", -1)) < 0: return false
	var packet := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: packet[axis] = value
	target.owner.combat_units[int(target.unit)]["personality"] = packet
	return true

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "投靠測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
	if not _check(requested, "a neutral new world is requested", RegionEntry.menu_message): return
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
	if not _check(int(start_team.get("faction", -1)) == RegionFactionQuery.NEUTRAL_FACTION_ID and start_team.person_ids.size() == 1 + TerrainLab.INITIAL_CADRES, "the player captains a neutral start team with cadres", start_team): return
	var cadres: Array[int] = []
	for person: Variant in start_team.person_ids:
		if int(person) != player: cadres.append(int(person))
	var official := cadres[0]
	var stubborn := cadres[1]

	# A new faction whose king is the official, prepared first so its id is in the registry before the Site uses it.
	var official_ref: Dictionary = JoinFaction._world_ref(controller, official)
	if not _check(not official_ref.is_empty(), "the official has a world person ref", official_ref): return
	var revision := int(slot.control.get("faction_registry", {}).get("revision", 0))
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, revision, [], {"name": "乙國", "kind": "npc", "leader_ref": official_ref, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "a faction with the official as king is prepared", prepared): return
	var faction := int(prepared.faction_id)
	var old_team_id := int(start_team.team_id)
	var detached: Dictionary = lab.crowd_site.detach_to_new_team(official, faction)
	if not _check(detached.ok, "the official leaves the start team as captain of his own team", detached): return
	var official_team: Dictionary = _team_of(lab, official)
	var official_roster: Dictionary = lab.crowd_site.native_roster(int(official_team.get("team_id", -1)))
	if not _check(int(official_team.get("faction", -1)) == faction and official_team.person_ids.size() == 1 and int(official_roster.get("formal_commander", -1)) == 0, "the official's new team is his faction, one person, with him as captain", [official_team, official_roster.get("formal_commander")]): return
	var old_roster: Dictionary = lab.crowd_site.native_roster(old_team_id)
	if not _check(not lab.crowd_site.roster_post_holders(old_team_id).has(official) and CrowdSite._roster_index_for_person(old_roster, player) == int(old_roster.formal_commander), "the old team vacated his posts and keeps the player as captain"): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	if not _check(captured.ok, "the Site captures for a checkpoint", captured): return
	var saved: Dictionary = slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured)
	if not _check(saved.ok, "the founded faction and the detached official save", saved): return

	var minds_set := _set_personality(lab, stubborn, 100) and _set_personality(lab, player, 50) and _set_personality(lab, official, 50)
	for cadre: int in cadres:
		if cadre != stubborn and cadre != official: minds_set = minds_set and _set_personality(lab, cadre, 50)
	if not _check(minds_set, "the stubborn cadre's personality is set far from the player's and the official's"): return
	var registry_before: Dictionary = slot.control.faction_registry.duplicate(true)
	var preview: Dictionary = controller.preview_join_faction(official)
	if not _check(preview.ok and preview.accepted, "the official would accept the player", preview): return
	var leaving: Array = []
	for cadre: Dictionary in preview.cadres:
		if not cadre.follows: leaving.append(int(cadre.id))
	if not _check(leaving == [stubborn], "only the stubborn cadre would not follow", preview.cadres): return
	if not _check(slot.control.faction_registry == registry_before and int(_team_of(lab, player).faction) == RegionFactionQuery.NEUTRAL_FACTION_ID, "the preview changes nothing"): return

	var joined: Dictionary = JoinFaction.join(controller, official)
	if not _check(joined.ok, "joining in person succeeds", joined): return
	var team: Dictionary = _team_of(lab, player)
	if not _check(int(team.faction) == faction and not team.person_ids.has(stubborn) and team.person_ids.size() == TerrainLab.INITIAL_CADRES - 1, "the team is the faction without the stubborn cadre", team): return
	var alone: Dictionary = _team_of(lab, stubborn)
	var alone_roster: Dictionary = lab.crowd_site.native_roster(int(alone.get("team_id", -1)))
	if not _check(int(alone.get("faction", -1)) == RegionFactionQuery.NEUTRAL_FACTION_ID and alone.person_ids.size() == 1 and int(alone_roster.get("formal_commander", -1)) == 0, "the stubborn cadre captains his own one-person neutral team", alone): return
	var registry: Dictionary = slot.control.faction_registry
	var sworn: Dictionary = RegionPeerage.record_of(registry, JoinFaction._world_ref(controller, player))
	if not _check(sworn.get("rank") == "none" and int(sworn.get("faction_id", -1)) == faction and RegionPeerage.same_ref(sworn.get("liege_ref"), official_ref), "the player is sworn to the official, untitled, in the saved registry", sworn): return
	if not _check(RegionPeerage.record_of(registry, official_ref).get("rank") == "king", "the official is still the faction's king"): return
	var again: Dictionary = JoinFaction.join(controller, official)
	if not _check(not again.ok and again.get("code") == "NOT_NEUTRAL", "a second join is refused", again): return
	_finished = true
	print("REGION_JOIN_FACTION_PASS: ", checks, " checks; a cadre detaches in place, the preview and the in-person join hold, refusing cadres stay neutral")
	quit(0)
