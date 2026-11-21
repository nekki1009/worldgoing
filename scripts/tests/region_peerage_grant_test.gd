extends SceneTree
## Peerage step 3 in a live world. The player founds his own faction at the start (he is its king). Checks:
## - granting a rank to a cadre without fiefs is refused by the fief minimum, and nothing is saved;
## - a granted baron (registry candidate with a village fief) saves through the controller's commit;
## - revoking it ends the title; proclaiming emperor without a granted king is refused;
## - a titled person's death is queued and applied at the next Region checkpoint (family rule; no heir ends it);
## - the checkpoint re-indexes this Site's fiefs (no settlement here: nobody holds this Site).
## Output: REGION_PEERAGE_GRANT_PASS on success; quit(1) on any failure or the deadline.

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
	printerr("REGION_PEERAGE_GRANT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_PEERAGE_GRANT OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "授爵測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"})
	if not _check(requested, "a found-faction world is requested", RegionEntry.menu_message): return
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
	var player_ref: Variant = slot.peerage_person_ref(player)
	if not _check(RegionPeerage.record_of(slot.control.faction_registry, player_ref).get("rank") == "king", "the founder is king"): return
	var founder_rep: Dictionary = controller.reputation_of(player)
	if not _check(int(founder_rep.prestige) == 6000 and int(founder_rep.credit) == 0, "founding a kingdom: king floor 50 + 10 prestige, credit 0", founder_rep): return
	var cadre := -1
	for team: Dictionary in lab.crowd_site.teams:
		if team.get("person_ids", []).has(player):
			for person: Variant in team.person_ids:
				if int(person) != player: cadre = int(person)
	if not _check(cadre > 0, "the start team has a cadre"): return
	var cadre_ref: Variant = slot.peerage_person_ref(cadre)

	var revision := int(slot.control.faction_registry.revision)
	var refused: Dictionary = controller.grant_title(cadre, "baron")
	if not _check(not refused.ok and refused.get("code") == "FIEF_MINIMUM" and int(slot.control.faction_registry.revision) == revision, "a baron without a village is refused and nothing is saved", refused): return

	var candidate: Dictionary = RegionPeerage.grant(slot.control.faction_registry, player_ref, cadre_ref, "baron", [2], float(slot.control.logical_game_seconds))
	var granted: Dictionary = controller._commit_peerage(candidate, "已授予男爵")
	if not _check(granted.ok and RegionPeerage.record_of(slot.control.faction_registry, cadre_ref).get("rank") == "baron", "a baron candidate commits through the Region checkpoint", granted): return
	if not _check(RegionPeerage.fiefs_of(slot.control.faction_registry, cadre_ref).is_empty(), "the checkpoint indexes no fief here (this Site has no settlement)"): return

	if not _check(int(controller.reputation_of(cadre).prestige) == 1200, "a baron's prestige reads at least the baron floor 12"): return
	var revoked: Dictionary = controller.revoke_title(cadre)
	if not _check(revoked.ok and RegionPeerage.record_of(slot.control.faction_registry, cadre_ref).is_empty(), "the king revokes the baron", revoked): return
	if not _check(int(controller.reputation_of(cadre).prestige) == 0, "revoking costs the floor difference (12 -> 0)", controller.reputation_of(cadre)): return
	var emperor: Dictionary = controller.proclaim_emperor()
	if not _check(not emperor.ok and emperor.get("code") == "NEEDS_KING", "an emperor needs a granted king", emperor): return

	candidate = RegionPeerage.grant(slot.control.faction_registry, player_ref, cadre_ref, "baron", [2], float(slot.control.logical_game_seconds))
	if not _check(controller._commit_peerage(candidate, "已授予男爵").ok, "the baron is granted again"): return
	# Reputation events: a broken team's captain loses 2; capturing a baron gives the captor's captain 0.2 x 12.
	var team_id := -1
	for team: Dictionary in lab.crowd_site.teams:
		if team.get("person_ids", []).has(player): team_id = int(team.team_id)
	controller.team_routed_reputation(team_id)
	if not _check(int(controller.reputation_of(player).prestige) == 5800, "the routed team's captain loses 2 (no hostile team here wins anything)", controller.reputation_of(player)): return
	controller._captivity_reputation(cadre, player)
	if not _check(int(controller.reputation_of(player).prestige) == 6040 and int(controller.reputation_of(cadre).prestige) == 1200, "capturing a baron gives +2.4; the captured baron stays at his floor", [controller.reputation_of(player), controller.reputation_of(cadre)]): return
	var heir := controller.peerage_heir_of(cadre)
	controller._queue_peerage_inheritance(cadre)
	if not _check(slot.pending_peerage_inheritance.size() == 1, "the baron's death is queued for the next checkpoint", slot.pending_peerage_inheritance): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	var saved: Dictionary = slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, {}, false, captured) if captured.ok else captured
	if not _check(saved.ok and slot.pending_peerage_inheritance.is_empty(), "the next checkpoint applies the queued inheritance", saved): return
	var after: Dictionary = RegionPeerage.record_of(slot.control.faction_registry, cadre_ref)
	if heir <= 0:
		if not _check(after.is_empty(), "without a family heir the title ends", after): return
	else:
		var heir_record: Dictionary = RegionPeerage.record_of(slot.control.faction_registry, slot.peerage_person_ref(heir))
		if not _check(after.is_empty() and not heir_record.is_empty(), "the family heir holds the title", heir_record): return
	_finished = true
	print("REGION_PEERAGE_GRANT_PASS: ", checks, " checks; grant minimums, commit, revoke, emperor gate and inheritance at checkpoint hold")
	quit(0)
