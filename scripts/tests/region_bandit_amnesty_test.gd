extends SceneTree
## Bandit B3 (reports/bandit-faction-spec.md §5.3, §6, §8; BA-05, BA-06, BA-11) in a live world. A new world opens with the
## 落草 start (the player chiefs a band of himself and five cadres). One cadre leaves as king of a new lawful faction 乙國 (the
## official); three cadres get a personality far from both, so they will not follow. Checks:
## - pure data: amnesty_end merges / disperses / hands over by the number who stay; the chief's will adds heat / 5;
## - preview: a member who is not the chief, or a lawful person posing as chief, is refused; the preview changes nothing;
## - amnesty: the player and the following cadre become 乙國, the chief swears to the official untitled, the three
##   stayers keep the band in the old team, whose captaincy passes to the most prestigious of them (the new chief), the
##   official gains 3 prestige, and the Region checkpoint saves it;
## - replace_chief with three free members hands over; disperse ends the band (extinct, lair cleared, id kept) and leaves
##   everyone in a one-person neutral team.
## Output: REGION_BANDIT_AMNESTY_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Amnesty = preload("res://scripts/terrain_lab/site_bandit_amnesty.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
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
	printerr("REGION_BANDIT_AMNESTY_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_BANDIT_AMNESTY OK ", checks, ": ", message)
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

func _data_checks() -> bool:
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var a := {"type": "person", "namespace": "amnesty_data", "lineage": 1}
	var b := {"type": "person", "namespace": "amnesty_data", "lineage": 2}
	var c := {"type": "person", "namespace": "amnesty_data", "lineage": 3}
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "官", "kind": "npc", "leader_ref": a})
	reg = made.registry
	var lawful := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "匪", "kind": "bandit", "leader_ref": b, "bandit": {"lair": {"site_id": "s", "cell": [1, 1]}}})
	reg = made.registry
	var band := int(made.faction_id)
	var merged: Dictionary = Bandit.amnesty_end(reg, band, lawful, 0, null, 10.0)
	if not _check(merged.ok and merged.registry.entries[str(band)].status == "merged" and int(merged.registry.entries[str(band)].merged_into) == lawful and merged.registry.entries[str(band)].bandit.lair == null, "nobody stays: the band merges into the accepting faction", merged): return false
	if not _check(RegionFactionQuery.resolve(merged.registry, band).get("faction_id") == lawful, "the merged id resolves to the accepting faction"): return false
	var gone: Dictionary = Bandit.amnesty_end(reg, band, lawful, 2, null, 10.0)
	if not _check(gone.ok and gone.registry.entries[str(band)].status == "extinct" and float(gone.registry.entries[str(band)].ended_at) == 10.0, "two stay: the band disperses (extinct)", gone): return false
	var kept: Dictionary = Bandit.amnesty_end(reg, band, lawful, 3, c, 10.0)
	if not _check(kept.ok and kept.registry.entries[str(band)].status == "active" and RegionPeerage.same_ref(kept.registry.entries[str(band)].leader_ref, c), "three stay: the band goes on under the heir", kept): return false
	if not _check(Bandit.amnesty_end(reg, band, band, 0, null, 10.0).get("code") == "NO_FACTION" and Bandit.amnesty_end(reg, lawful, band, 0, null, 10.0).get("code") == "NOT_BANDIT", "only a band ends into a lawful faction"): return false
	if not _check(Bandit.disperse(gone.registry, band, 11.0).get("code") == "NO_FACTION", "an ended band cannot disperse again"): return false
	var calm := {"version": 1}
	for axis: String in preload("res://scripts/terrain_lab/person_personality.gd").AXES: calm[axis] = 50
	if not _check(is_equal_approx(Bandit.chief_score(calm, calm, 50), 110.0) and is_equal_approx(Bandit.chief_score(calm, calm, 0), 100.0), "the chief's will adds heat / 5"): return false
	return true

func _run() -> void:
	if not _data_checks(): return
	var requested: bool = RegionEntry.request_new_world(START, {}, "招安測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "黑風寨"})
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
	var start_team: Dictionary = _team_of(lab, player)
	var band := int(start_team.get("faction", -1))
	if not _check(RegionFactionQuery.is_bandit(slot.control.faction_registry, band) and start_team.person_ids.size() == 1 + TerrainLab.INITIAL_CADRES, "the player chiefs a band of himself and his cadres", start_team): return
	var cadres: Array[int] = []
	for person: Variant in start_team.person_ids:
		if int(person) != player: cadres.append(int(person))
	var official := cadres[0]
	var follower := cadres[1]
	var stubborn: Array[int] = [cadres[2], cadres[3], cadres[4]]

	var official_ref: Dictionary = JoinFaction._world_ref(controller, official)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [], {"name": "乙國", "kind": "npc", "leader_ref": official_ref, "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok, "a lawful faction with the official as king is prepared", prepared): return
	var faction := int(prepared.faction_id)
	var detached: Dictionary = lab.crowd_site.detach_to_new_team(official, faction)
	if not _check(detached.ok, "the official leaves the band as captain of his own team", detached): return
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	var saved: Dictionary = slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, prepared.registry, false, captured) if captured.ok else captured
	if not _check(saved.ok, "the lawful faction and the detached official save", saved): return
	var minds := _set_personality(lab, player, 50) and _set_personality(lab, official, 50) and _set_personality(lab, follower, 50)
	for person: int in stubborn: minds = minds and _set_personality(lab, person, 100)
	if not _check(minds, "personalities are set"): return

	var before: Dictionary = slot.control.faction_registry.duplicate(true)
	var not_chief: Dictionary = Amnesty.preview(controller, follower, official)
	if not _check(not not_chief.ok and not_chief.code == "NOT_CHIEF", "only the chief himself can talk amnesty", not_chief): return
	var swapped: Dictionary = Amnesty.preview(controller, official, player)
	if not _check(not swapped.ok and swapped.code == "NOT_BANDIT", "a lawful person is not a chief", swapped): return
	var seen: Dictionary = Amnesty.preview(controller, player, official)
	var shown: Dictionary = controller.bandit_amnesty(official, true)
	if not _check(shown.ok and str(shown.message).contains("頭目願意受撫"), "the controller preview reads the player as the chief", shown.get("message")): return
	if not _check(seen.ok and seen.accepted and seen.chief_willing, "the official would take the band in; the player chief is willing", seen): return
	var staying: Array = []
	for row: Dictionary in seen.members:
		if not row.follows: staying.append(int(row.id))
	staying.sort()
	if not _check(staying == [stubborn[0], stubborn[1], stubborn[2]], "only the three far-minded cadres would stay", seen.members): return
	if not _check(slot.control.faction_registry == before and int(_team_of(lab, player).faction) == band, "the preview changes nothing"): return

	var prestige_before := int(controller.reputation_of(official).prestige)
	var done: Dictionary = Amnesty.amnesty(controller, player, official)
	if not _check(done.ok, "the amnesty goes through", done): return
	var registry: Dictionary = slot.control.faction_registry
	var mine: Dictionary = _team_of(lab, player)
	var theirs: Dictionary = _team_of(lab, follower)
	if not _check(int(mine.faction) == faction and int(theirs.faction) == faction and not mine.person_ids.has(stubborn[0]), "the player and the follower are 乙國", [mine, theirs]): return
	var sworn: Dictionary = RegionPeerage.record_of(registry, JoinFaction._world_ref(controller, player))
	if not _check(sworn.get("rank") == "none" and int(sworn.get("faction_id", -1)) == faction and RegionPeerage.same_ref(sworn.get("liege_ref"), official_ref), "the old chief swears to the official, untitled", sworn): return
	var heir := int(done.heir)
	if not _check(stubborn.has(heir) and registry.entries[str(band)].status == "active" and RegionPeerage.same_ref(registry.entries[str(band)].leader_ref, JoinFaction._world_ref(controller, heir)), "the band goes on under one of the stayers", [heir, registry.entries[str(band)]]): return
	var kept_team: Dictionary = _team_of(lab, heir)
	var kept_roster: Dictionary = lab.crowd_site.native_roster(int(kept_team.get("team_id", -1)))
	var kept_people: Array = kept_team.get("person_ids", []).duplicate()
	kept_people.sort()
	if not _check(int(kept_team.get("faction", -1)) == band and kept_people == [stubborn[0], stubborn[1], stubborn[2]] and int(kept_roster.units[int(kept_roster.formal_commander)].person_id) == heir and int(kept_team.team_id) == int(start_team.team_id), "the stayers keep the old team under the new chief as its captain", [kept_team, kept_roster.get("formal_commander")]): return
	var native_state: Dictionary = lab.crowd_site.formation_state(int(lab.crowd_site.native_owner(int(kept_team.team_id)).formation_index))
	if not _check(int(native_state.get("formal_person", -1)) == heir, "the native formation names the new captain", native_state.get("formal_person")): return
	if not _check(int(controller.reputation_of(official).prestige) - prestige_before == Bandit.AMNESTY_PRESTIGE * Reputation.SCALE, "the official gains 3 prestige", [prestige_before, controller.reputation_of(official)]): return
	var again: Dictionary = Amnesty.preview(controller, player, official)
	if not _check(not again.ok and again.code == "NOT_BANDIT", "the old chief is no longer a bandit", again): return

	var replaced: Dictionary = Amnesty.replace_chief(controller, band)
	if not _check(replaced.ok and stubborn.has(int(replaced.heir)), "three free members: the most prestigious takes over", replaced): return
	var dispersed: Dictionary = Amnesty.disperse(controller, band)
	if not _check(dispersed.ok, "the band disperses", dispersed): return
	registry = slot.control.faction_registry
	var ended: Dictionary = registry.entries[str(band)]
	if not _check(ended.status == "extinct" and ended.ended_at != null and ended.bandit.lair == null and RegionFactionQuery.is_bandit(registry, band), "the band is extinct, its lair cleared, its id kept", ended): return
	for person: int in stubborn:
		var alone: Dictionary = _team_of(lab, person)
		if not _check(int(alone.get("faction", -1)) == RegionFactionQuery.NEUTRAL_FACTION_ID and alone.person_ids.size() == 1, "#%d is a one-person neutral team" % person, alone): return
	if not _check(Amnesty.replace_chief(controller, band).get("code") == "NO_MEMBERS" and int(registry.next_faction_id) > band, "nothing is left of the band; its id is never reused"): return
	_finished = true
	print("REGION_BANDIT_AMNESTY_PASS: ", checks, " checks; amnesty in person, stayers keep or disperse the band, succession and dispersal")
	quit(0)
