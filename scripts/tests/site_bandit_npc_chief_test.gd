extends SceneTree
## 土匪 B4 (bandit spec §10, §11): a player-made band (落草, raid AI off: the chief decides) runs on its own once an NPC
## holds the chief's seat. A 落草 world opens (the player chiefs a band of himself and five cadres, lair here). Checks:
## - while the player is chief, the band's day does nothing and its raid AI stays off;
## - after the chief's seat passes to a cadre, the next day switches the raid AI on, saves it, and the band takes its
##   daily decisions from then on (the switch is reported once).
## Output: SITE_BANDIT_NPC_CHIEF_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const BanditDay = preload("res://scripts/terrain_lab/site_bandit_day.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
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
	printerr("SITE_BANDIT_NPC_CHIEF_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_NPC_CHIEF OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _row(day: Dictionary, band: int) -> Dictionary:
	for action: Dictionary in day.get("actions", []):
		if int(action.band) == band: return action
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "接寨世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	if not _check(not bool(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).raid_ai), "a player-made band starts with its raid AI off"): return
	var held: Dictionary = BanditDay.run(controller, 3)
	if not _check(_row(held, band).is_empty() and not bool(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).raid_ai), "while the player is chief the band's day does nothing", held): return
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	var succeeded: Dictionary = Bandit.succeed(slot.control.faction_registry, band, JoinFaction._world_ref(controller, cadres[0]), float(slot.control.logical_game_seconds))
	if not _check(succeeded.ok and controller._commit_diplomacy(succeeded, "").ok, "the chief's seat passes to a cadre", succeeded): return
	var taken: Dictionary = BanditDay.run(controller, 4)
	if not _check(str(_row(taken, band).get("action", "")) == "npc_takes_over" and bool(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).raid_ai), "the next day the band's raid AI is on", taken): return
	var again: Dictionary = BanditDay.run(controller, 5)
	if not _check(str(_row(again, band).get("action", "")) != "npc_takes_over", "the switch is reported once", again): return
	_finished = true
	print("SITE_BANDIT_NPC_CHIEF_PASS: ", checks, " checks; an NPC chief's band runs on its own")
	quit(0)
