extends SceneTree
## 土匪 B4d-2 in a live world (reports/bandit-faction-spec.md §4 B, §12): routed survivors form a band.
## A 落草 world opens (the player chiefs a band of himself and five cadres). The band's team routs (the closed battle's
## routed teams are remembered), then the band disperses: it is extinct and everyone stands in a one-person neutral team.
## Checks:
## - the watch holds the five cadres, never the controlled person, and passes the save rules (Region checkpoint saves it);
## - day +3: still waiting, nothing forms;
## - day +7: the five form a new band (origin rout) led by the most prestigious, lair at his cell on this Site, each
##   cadre's team in the band, the player left out, the watch cleared, a notice written;
## - a watch whose faction is alive and whose team still exists is dropped (has a home).
## Output: SITE_BANDIT_ROUT_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Amnesty = preload("res://scripts/terrain_lab/site_bandit_amnesty.gd")
const Rout = preload("res://scripts/terrain_lab/site_bandit_rout.gd")
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
	printerr("SITE_BANDIT_ROUT_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_BANDIT_ROUT OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "潰兵成伙世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "黑風寨"})
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
	var team_id := int(start_team.team_id)
	var cadres: Array[int] = []
	for person: Variant in start_team.person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(RegionFactionQuery.is_bandit(slot.control.faction_registry, band) and cadres.size() == TerrainLab.INITIAL_CADRES and cadres.size() >= 3, "the player chiefs a band of himself and his cadres", start_team): return

	# The band's team routs in a battle that closes.
	Rout.remember(controller, {team_id: band})
	var watch: Dictionary = lab.terrain.site.get(Rout.SECTION, {})
	var record: Dictionary = watch.get(str(team_id), {})
	var today := Rout.day_of(controller)
	if not _check(int(record.get("faction", -1)) == band and int(record.get("day", -1)) == today and record.get("members", []) == cadres, "the routed team's people are remembered without the player", watch): return
	if not _check(Rout.validate(lab.terrain.site).ok, "the watch passes the save rules"): return
	var dispersed: Dictionary = Amnesty.disperse(controller, band)
	if not _check(dispersed.ok and slot.control.faction_registry.entries[str(band)].status == "extinct", "the band disperses (extinct); its people stand alone", dispersed): return
	if not _check(lab.terrain.site.get(Rout.SECTION, {}).has(str(team_id)), "the watch is saved with the Site checkpoint"): return
	var bad: Dictionary = {Rout.SECTION: {"x": {"faction": 1, "day": 0, "members": []}}}
	if not _check(not Rout.validate(bad).ok and not Rout.validate({Rout.SECTION: {"1": {"faction": 1.5, "day": 0, "members": []}}}).ok, "malformed watches are refused"): return

	var waiting: Dictionary = Rout.day(controller, today + 3)
	if not _check(waiting.formed.is_empty() and waiting.dropped.is_empty() and lab.terrain.site.get(Rout.SECTION, {}).has(str(team_id)), "day +3: they are still waiting", waiting): return
	var best := -1
	var best_prestige := -1
	for person: int in cadres:
		var prestige := int(controller.reputation_of(person).prestige)
		if prestige > best_prestige or prestige == best_prestige and person < best:
			best = person
			best_prestige = prestige
	var chief_cell: Vector2i = lab.crowd_site.combat_target(best).cell
	var bands_before := int(slot.control.faction_registry.next_faction_id)
	var formed: Dictionary = Rout.day(controller, today + Bandit.FORM_WAIT_DAYS)
	if not _check(formed.formed.size() == 1 and formed.dropped.is_empty(), "day +7: one band forms", formed): return
	var new_band := int(formed.formed[0].band)
	var registry: Dictionary = slot.control.faction_registry
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, new_band)
	if not _check(new_band >= bands_before and new_band != band and RegionFactionQuery.is_bandit(registry, new_band) and table.origin == "rout"
		and RegionPeerage.same_ref(registry.entries[str(new_band)].leader_ref, JoinFaction._world_ref(controller, best)), "a new band of origin rout, led by the most prestigious survivor", registry.entries.get(str(new_band))): return
	if not _check(str(table.lair.site_id) == str(lab.terrain.site.id) and table.lair.cell == [chief_cell.x, chief_cell.y], "its lair is at the chief's cell on this Site", table.lair): return
	for person: int in cadres:
		if not _check(int(_team_of(lab, person).get("faction", -1)) == new_band, "#%d is in the new band" % person, _team_of(lab, person)): return
	if not _check(int(_team_of(lab, player).faction) != new_band and not lab.terrain.site.has(Rout.SECTION), "the player is left out; the watch is cleared", _team_of(lab, player)): return
	var noticed := false
	for notice: Variant in lab.terrain.site.get("notices", []):
		if str(notice).contains("潰兵") and str(notice).contains("落草成伙"): noticed = true
	if not _check(noticed, "a notice tells of the new band"): return

	# A routed team with a home does not turn bandit.
	var chief_team: Dictionary = _team_of(lab, best)
	Rout.remember(controller, {int(chief_team.team_id): int(chief_team.faction)})
	var homed: Dictionary = Rout.day(controller, today + 30)
	if not _check(homed.formed.is_empty() and homed.dropped.size() == 1 and str(homed.dropped[0].reason) == "has_home" and not lab.terrain.site.has(Rout.SECTION), "a watch with a home (or nobody left) is dropped", homed): return
	_finished = true
	print("SITE_BANDIT_ROUT_PASS: ", checks, " checks; routed survivors without a home form a band after 7 days")
	quit(0)
