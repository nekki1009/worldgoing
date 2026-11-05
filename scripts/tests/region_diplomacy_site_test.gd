extends SceneTree
## Diplomacy in a live world. The player founds 甲國 (its king); a cadre leaves as king of 乙國 in the same Site. Checks:
## - the NPC day (§11.6): the weaker 乙國 asks for a 15-day truce, delivered at once, once per game day;
## - the player head accepts the oldest letter; the pair is at truce and the native slots are re-armed;
## - declaring war while at peace is a breach (credit -20) and the pair is hostile again.
## Output: REGION_DIPLOMACY_SITE_PASS on success; quit(1) on any failure or the deadline.

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
	printerr("REGION_DIPLOMACY_SITE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_DIPLOMACY_SITE OK ", checks, ": ", message)
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
	var requested: bool = RegionEntry.request_new_world(START, {}, "外交測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"})
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
	if not _check(start_team.person_ids.size() == 1 + TerrainLab.INITIAL_CADRES, "the player captains a start team with cadres", start_team): return
	var mine := controller.diplomacy_head_faction()
	if not _check(mine >= 0 and mine == int(start_team.faction), "the founder heads his faction", [mine, start_team.faction]): return
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

	var location_a: Variant = controller.diplomacy_site_of(slot.peerage_person_ref(player))
	if not _check(location_a != null and controller.diplomacy_distance_m(mine, faction) == 0.0, "both heads are in this Site: no letter delay", location_a): return
	# NPC day (§11.6): 乙國 (1 person) faces 甲國 (5): r = 0.2 < 0.5 with a neutral head, so it asks for a 15-day truce.
	if not _check(_set_personality(lab, official, 50), "the NPC head has a neutral personality (A = M = 50)"): return
	controller._npc_diplomacy_day = -1
	var npc: Dictionary = controller.npc_diplomacy_day()
	if not _check(npc.get("ok", false), "the NPC day commits its own move", npc): return
	controller.settle_diplomacy()
	var letters: Dictionary = RegionDiplomacy.table(slot.control.faction_registry).proposals
	var asked: Dictionary = letters.values()[0] if letters.size() == 1 else {}
	if not _check(int(asked.get("from", -1)) == faction and int(asked.get("to", -1)) == mine and asked.get("kind") == "truce" and int(asked.get("days", 0)) == 15 and asked.get("status") == "delivered", "the weaker NPC head asks for a 15-day truce, delivered at once", letters): return
	if not _check(controller.npc_diplomacy_day().is_empty(), "the NPC acts at most once per game day"): return
	if not _check(controller.propose_diplomacy(faction, "truce", 10).get("code") == "PENDING", "the same pair and kind cannot have two open letters"): return
	var accepted: Dictionary = controller.answer_oldest_letter(true)
	if not _check(accepted.ok, "the head accepts the oldest letter", accepted): return
	controller.settle_diplomacy()
	var now := float(slot.control.logical_game_seconds)
	if not _check(not RegionDiplomacy.hostile(slot.control.faction_registry, mine, faction, now) and lab.crowd_site._apply_slot_alliances(), "the pair is at truce and the native slots are re-armed"): return
	var status: Dictionary = controller.diplomacy_status()
	if not _check(status.ok and str(status.message).contains("停戰"), "the status shows the truce", status): return
	var war: Dictionary = controller.declare_war_on(faction)
	if not _check(war.ok and RegionDiplomacy.hostile(slot.control.faction_registry, mine, faction, now) and RegionDiplomacy.table(slot.control.faction_registry).breaches.size() == 1, "war during a truce is a breach and the pair is hostile again", war): return
	if not _check(int(controller.reputation_of(player).credit) == -2000, "breaking the truce costs 20 credit", controller.reputation_of(player)): return
	_finished = true
	print("REGION_DIPLOMACY_SITE_PASS: ", checks, " checks; NPC truce request, acceptance, native re-arm and breach hold")
	quit(0)
