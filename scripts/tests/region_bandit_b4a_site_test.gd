extends SceneTree
## Bandit B4a in a live world (reports/bandit-faction-spec.md §9, §10; BA-07/BA-08 player side). A neutral world opens;
## the player's start team becomes a rebel faction he leads (no nation, no settlement, no fief). Checks:
## - go_outlaw: the rebel faction becomes a band (same id, origin fallen_rebel, converted_from rebel), the player's title
##   ends, his credit falls 20, the band is hostile to neutral and refuses diplomacy, the Region checkpoint saves it;
## - bandit_rise: refused with the missing condition (prestige below 30) and nothing changes;
## - a second go_outlaw is refused (already a bandit).
## Output: REGION_BANDIT_B4A_SITE_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_BANDIT_B4A_SITE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_B4A_SITE OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "落草叛軍世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"}), "a neutral world is requested", RegionEntry.menu_message): return
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
	var player_ref: Dictionary = JoinFaction._world_ref(controller, player)
	var team_id := int(lab._original_person_target(player).owner.team_id)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [], {"name": "流亡軍", "kind": "rebel", "leader_ref": player_ref, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "a rebel faction led by the player is prepared", prepared): return
	var rebels := int(prepared.faction_id)
	if not _check(lab.relabel_team_faction(team_id, rebels).ok, "the start team joins it"): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	var saved: Dictionary = slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured) if captured.ok else captured
	if not _check(saved.ok and RegionPeerage.record_of(slot.control.faction_registry, player_ref).get("rank") == "king", "the rebel faction saves with the player as its king", saved): return
	var credit_before := int(controller.reputation_of(player).credit)

	var fell: Dictionary = controller.go_outlaw("")
	if not _check(fell.ok, "the rebel head goes outlaw", fell): return
	var registry: Dictionary = slot.control.faction_registry
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, rebels)
	if not _check(RegionFactionQuery.is_bandit(registry, rebels) and table.origin == "fallen_rebel" and table.converted_from.kind == "rebel" and table.lair is Dictionary and str(table.lair.site_id) == str(lab.terrain.site.id), "the faction is now a band that fell from rebellion, with a lair here", table): return
	if not _check(RegionPeerage.record_of(registry, player_ref).is_empty() and RegionPeerage.same_ref(registry.entries[str(rebels)].leader_ref, player_ref), "the player's title ends; he is the chief", registry.entries[str(rebels)]): return
	if not _check(int(controller.reputation_of(player).credit) - credit_before == Reputation.OUTLAW * Reputation.SCALE, "going outlaw costs 20 credit", controller.reputation_of(player)): return
	var now := float(slot.control.logical_game_seconds)
	if not _check(RegionDiplomacy.hostile(registry, rebels, RegionFactionQuery.NEUTRAL_FACTION_ID, now) and RegionDiplomacy.propose(registry, rebels, RegionFactionQuery.NEUTRAL_FACTION_ID, "truce", 5, player_ref, 0.0, now).get("code") == "BANDIT_NO_DIPLOMACY", "the band is hostile and has no diplomacy"): return

	var before: Dictionary = slot.control.faction_registry.duplicate(true)
	var rise: Dictionary = controller.bandit_rise()
	if not _check(not rise.ok and rise.code == "RISE_PRESTIGE" and slot.control.faction_registry == before, "rising is refused below 30 prestige and changes nothing", rise): return
	var again: Dictionary = controller.go_outlaw("")
	if not _check(not again.ok and again.code == "ALREADY", "a second 落草 is refused", again): return
	_finished = true
	print("REGION_BANDIT_B4A_SITE_PASS: ", checks, " checks; a lawless rebel head goes outlaw, rising is gated")
	quit(0)
