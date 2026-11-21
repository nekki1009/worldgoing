extends SceneTree
## 平民 C3 (reports/civilian-site-behavior-plan.md §4.5): harming civilians costs the striker credit. A neutral world opens
## with the player and his cadres; one cadre leaves into his own neutral team as a civilian, another stays a soldier.
## Checks (SiteController.civilian_harmed, called by the crowd battle log on every DEATH / KO with a known striker):
## - killing a civilian of another side costs 2 credit, knocking one out 1;
## - a soldier victim, the striker himself, or a civilian of the striker's own (non-neutral) faction costs nothing.
## Output: SITE_CIVILIAN_HARM_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
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
	printerr("SITE_CIVILIAN_HARM_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVILIAN_HARM OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "平民聲望世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var own := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 3, "the player has cadres", cadres): return
	var outsider := cadres[0]
	var left: Dictionary = lab.crowd_site.detach_to_new_team(outsider, RegionFactionQuery.NEUTRAL_FACTION_ID)
	if not _check(left.ok, "a cadre leaves into his own neutral team", left): return
	if not _check(lab.crowd_site.native_set_military_role(outsider, "civilian").ok and lab.crowd_site.native_set_military_role(cadres[1], "civilian").ok, "two people are civilians"): return
	var soldier := cadres[2]
	var credit := func() -> int: return int(controller.reputation_of(player).credit)

	var start: int = credit.call()
	controller.civilian_harmed(1, outsider, player)
	if not _check(credit.call() - start == Reputation.CIVILIAN_KO * Reputation.SCALE, "knocking out a civilian of another side costs 1 credit", [start, credit.call()]): return
	start = credit.call()
	controller.civilian_harmed(0, outsider, player)
	if not _check(credit.call() - start == Reputation.CIVILIAN_KILLED * Reputation.SCALE, "killing a civilian of another side costs 2 credit", [start, credit.call()]): return
	start = credit.call()
	controller.civilian_harmed(0, soldier, player)
	controller.civilian_harmed(0, player, player)
	controller.civilian_harmed(0, cadres[1], player)
	if not _check(credit.call() == start and own != RegionFactionQuery.NEUTRAL_FACTION_ID, "a soldier, oneself or a civilian of one's own faction costs nothing", [start, credit.call(), own]): return
	_finished = true
	print("SITE_CIVILIAN_HARM_PASS: ", checks, " checks; harming civilians of another side costs credit")
	quit(0)
