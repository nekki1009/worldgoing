extends SceneTree
## 平民 C4b (reports/civilian-site-behavior-plan.md §4.6, §4.7): discontented households leave or go outlaw.
## A world opens with a founded faction (the player and his cadres). Checks:
## - judge (pure): only every 30th day; a household below G 60 never leaves; at G 100 it always leaves and, at G >= 80,
##   half the rolls make it outlaw; the roll is the same on a second call (no re-roll);
## - depart, outlaw: two cadres gather into one team under the first, the team becomes a new band (origin refugee) led by
##   him with its lair at his cell, their housing registrations end;
## - depart, emigrate: two other cadres gather into one neutral team and their head takes them onto the Region map
##   (captain dispatch, reason emigrate): a travelling NPC party holds them and they are gone from the Site.
## The settlement and housing used by judge are test-only stand-ins, removed before anything saves.
## Output: SITE_RESIDENT_EXODUS_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Exodus = preload("res://scripts/terrain_lab/site_resident_exodus.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_RESIDENT_EXODUS_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_EXODUS OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _set_g(controller: SiteController, identity: int, g: int) -> void:
	var body: Variant = controller.person_actions._person(identity, false).body
	SiteSocial.relation(SiteSocial.state_of(body), ProduceTax.settlement_ref(controller.lab.terrain)).G = g

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "居民出走世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var own := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 4, "the player has four cadres", cadres): return

	# judge, over test-only stand-ins.
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "exodus_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["housing"] = {str(cadres[0]): {"version": 1, "house_id": "h1", "cell": 0}, str(cadres[1]): {"version": 1, "house_id": "h1", "cell": 1},
		str(cadres[2]): {"version": 1, "house_id": "h2", "cell": 0}, str(cadres[3]): {"version": 1, "house_id": "h2", "cell": 1}}
	for person: int in cadres.slice(0, 2): _set_g(controller, person, 100)
	for person: int in cadres.slice(2, 4): _set_g(controller, person, 59)
	var seed := 12345
	if not _check(Exodus.judge(controller, 31, seed).is_empty(), "nobody leaves off the 30-day mark"): return
	var verdicts: Array = Exodus.judge(controller, 30, seed)
	if not _check(verdicts.size() == 1 and str(verdicts[0].house_id) == "h1" and verdicts[0].members == [cadres[0], cadres[1]] and is_equal_approx(float(verdicts[0].mean), 100.0), "at G 100 the household leaves; below 60 it stays", verdicts): return
	if not _check(Exodus.judge(controller, 30, seed) == verdicts, "a second judgement rolls the same"): return
	var outlaws := 0
	for day: int in range(30, 30 * 41, 30):
		for verdict: Dictionary in Exodus.judge(controller, day, seed): outlaws += int(bool(verdict.outlaw))
	if not _check(outlaws > 5 and outlaws < 35, "about half of the G 100 departures go outlaw", outlaws): return
	if not _check(is_equal_approx(Exodus.leave_chance(59.0), 0.0) and is_equal_approx(Exodus.leave_chance(60.0), 0.2) and is_equal_approx(Exodus.leave_chance(80.0), 0.6), "the leave chance is (G - 50) / 50 from 60"): return
	lab.terrain.site.erase("settlement")
	lab.terrain.site["housing"] = {str(cadres[0]): {"version": 1, "house_id": "h1", "cell": 0}}

	# depart, outlaw: the stand-in housing of the leader ends with him.
	var outlawed: Dictionary = Exodus.depart(controller, [cadres[0], cadres[1]], true)
	if not _check(outlawed.ok, "the first household goes outlaw", outlawed): return
	var registry: Dictionary = slot.control.faction_registry
	var band := int(outlawed.band)
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	var cell: Vector2i = lab.crowd_site.combat_target(cadres[0]).cell
	if not _check(RegionFactionQuery.is_bandit(registry, band) and table.origin == "refugee" and RegionPeerage.same_ref(registry.entries[str(band)].leader_ref, JoinFaction._world_ref(controller, cadres[0]))
		and table.lair.cell == [cell.x, cell.y], "a new band of origin refugee led by the household's first member", registry.entries.get(str(band))): return
	var band_team: Dictionary = _team_of(lab, cadres[0])
	if not _check(int(band_team.faction) == band and band_team.person_ids.has(cadres[1]) and band_team.person_ids.size() == 2 and not lab.terrain.site.get("housing", {}).has(str(cadres[0])), "both are in the band's one team; the registration ended", band_team): return

	# depart, emigrate.
	var gone: Dictionary = Exodus.depart(controller, [cadres[2], cadres[3]], false)
	if not _check(gone.ok and not bool(gone.get("pending", false)), "the second household gathers and its head takes them onto the map", gone): return
	var party: Dictionary = slot.region_registry().parties.get(str(gone.token), {})
	if not _check(str(party.get("phase", "")) == "travelling" and str(party.get("transfer_receipt", {}).get("captain_dispatch", "")) == "emigrate", "a travelling NPC party carries them, sent by their head", party): return
	if not _check(_team_of(lab, cadres[2]).is_empty() and _team_of(lab, cadres[3]).is_empty(), "they are gone from the Site"): return
	_finished = true
	print("SITE_RESIDENT_EXODUS_PASS: ", checks, " checks; discontented households leave or go outlaw")
	quit(0)
