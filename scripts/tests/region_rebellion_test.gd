extends SceneTree
## Rebellion (plan step 5). Setup as the join test: a cadre becomes king of a new faction, the player joins him and is
## granted a barony (a candidate with a village). Checks:
## - an untitled or head person cannot rebel; a defect without an acceptor present is refused and changes nothing;
## - independent: a new faction exists with the player as its leader and king (no liege), the player's team is that
##   faction, his credit falls by 30, the old king keeps his own faction, and the checkpoint saves it.
## Output: REGION_REBELLION_PASS on success; quit(1) on any failure or the deadline.

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
	printerr("REGION_REBELLION_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_REBELLION OK ", checks, ": ", message)
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
	var requested: bool = RegionEntry.request_new_world(START, {}, "叛離測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
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

	var joined: Dictionary = JoinFaction.join(controller, official)
	if not _check(joined.ok, "the player joins the official's faction", joined): return
	var refused: Dictionary = controller.rebel("independent", -1, "叛國")
	if not _check(not refused.ok and refused.get("code") == "NOT_NOBLE", "an untitled sworn person cannot rebel with fiefs", refused): return
	var player_ref: Variant = slot.peerage_person_ref(player)
	var candidate: Dictionary = RegionPeerage.grant(slot.control.faction_registry, official_ref, player_ref, "baron", [2], float(slot.control.logical_game_seconds))
	if not _check(controller._commit_peerage(candidate, "男爵").ok and RegionPeerage.record_of(slot.control.faction_registry, player_ref).rank == "baron", "the king makes the player a baron"): return
	var revision_before := int(slot.control.faction_registry.revision)
	var no_acceptor: Dictionary = controller.rebel("defect", 999999, "")
	if not _check(not no_acceptor.ok and int(slot.control.faction_registry.revision) == revision_before and int(controller.reputation_of(player).credit) == 0, "a defect without an acceptor present is refused and changes nothing", no_acceptor): return
	var rebelled: Dictionary = controller.rebel("independent", -1, "叛國")
	if not _check(rebelled.ok, "the baron rebels and founds his own faction", rebelled): return
	var new_faction := int(rebelled.faction_id)
	var registry: Dictionary = slot.control.faction_registry
	var mine: Dictionary = RegionPeerage.record_of(registry, player_ref)
	if not _check(new_faction != faction and mine.get("rank") == "king" and mine.get("liege_ref") == null and int(mine.get("faction_id", -1)) == new_faction, "the rebel is king of the new faction", mine): return
	if not _check(RegionPeerage.same_ref(registry.entries[str(new_faction)].leader_ref, player_ref) and registry.entries[str(new_faction)].kind == "rebel", "the new faction's leader is the rebel", registry.entries[str(new_faction)]): return
	if not _check(int(_team_of(lab, player).faction) == new_faction, "the player's team belongs to the new faction"): return
	if not _check(int(controller.reputation_of(player).credit) == -3000, "independence costs 30 credit", controller.reputation_of(player)): return
	if not _check(RegionPeerage.record_of(registry, official_ref).get("rank") == "king" and int(RegionPeerage.record_of(registry, official_ref).faction_id) == faction, "the old king keeps his faction"): return
	if not _check(not RegionFactionQuery.same_side(new_faction, faction), "the old and the new faction are hostile"): return
	var synced: Dictionary = controller.sync_fief_owner()
	if not _check(synced.ok and not synced.changed, "a Site without a settlement has no fief to move", synced): return
	_finished = true
	print("REGION_REBELLION_PASS: ", checks, " checks; refusals, independence, credit penalty and the new faction hold")
	quit(0)
