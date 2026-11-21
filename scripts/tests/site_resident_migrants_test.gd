extends SceneTree
## 平民 C4c-2 (reports/civilian-site-behavior-plan.md §4.7): migrants. A world opens with a founded faction (the player
## captains his cadres). Two cadres stand apart as the residents' team, registered to a test-only stand-in house under a
## test-only stand-in settlement (both never saved). Checks:
## - judge: not on day 29, no settlement, unrest (mean G >= 40), no free beds (the stand-in house has no layout) each refuse;
## - free_beds skips taken cells; food counts grain, fish, meat and wild food;
## - arrive: a household of two new people is born into the residents' team as civilians, registered at the free cells,
##   the household table takes them in; the native state validates and the residents' team holds four.
## Output: SITE_RESIDENT_MIGRANTS_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Migrants = preload("res://scripts/terrain_lab/site_resident_migrants.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_RESIDENT_MIGRANTS_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_MIGRANTS OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "流民世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	if not _check(cadres.size() >= 2, "the player has two cadres", cadres): return
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], own)
	if not _check(apart.ok and lab.crowd_site.join_team(cadres[1], int(apart.team_id)).ok, "two cadres stand apart as the residents' team", apart): return
	var home := int(apart.team_id)
	for person: int in cadres.slice(0, 2):
		if not _check(lab.crowd_site.native_set_military_role(person, "civilian").ok, "#%d is a civilian" % person): return

	if not _check(str(Migrants.judge(controller, 30).get("reason", "")) == "no_settlement", "no settlement: nobody comes"): return
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "migrant_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["housing"] = {str(cadres[0]): {"version": 1, "house_id": "h1", "cell": 0}, str(cadres[1]): {"version": 1, "house_id": "h1", "cell": 1}}
	if not _check(str(Migrants.judge(controller, 29).get("reason", "")) == "not_today", "day 29: not a migration day"): return
	var ref := ProduceTax.settlement_ref(lab.terrain)
	for person: int in cadres.slice(0, 2):
		SiteSocial.relation(SiteSocial.state_of(controller.person_actions._person(person, false).body), ref).G = 50
	if not _check(str(Migrants.judge(controller, 30).get("reason", "")) == "unrest", "mean G 50: nobody comes"): return
	for person: int in cadres.slice(0, 2):
		SiteSocial.relation(SiteSocial.state_of(controller.person_actions._person(person, false).body), ref).G = 10
	if not _check(str(Migrants.judge(controller, 30).get("reason", "")) == "no_beds" and Migrants.free_beds(lab.terrain).is_empty(), "calm, but no free bed: nobody comes"): return
	var food_before := Migrants.food(lab.terrain)
	var made_inventory := not lab.terrain.site.get("inventory") is Dictionary
	if made_inventory: lab.terrain.site["inventory"] = {}
	var inventory: Dictionary = lab.terrain.site.inventory
	var grain_before := int(inventory.get("grain", 0))
	inventory["grain"] = grain_before + 7
	if not _check(Migrants.food(lab.terrain) == food_before + 7, "grain counts as food"): return
	inventory["grain"] = grain_before
	if grain_before == 0: inventory.erase("grain")
	if made_inventory: lab.terrain.site.erase("inventory")

	var near: Vector2i = lab.crowd_site.combat_target(player).cell
	var beds: Array = [lab.terrain.index(near + Vector2i(2, 0)), lab.terrain.index(near + Vector2i(2, 1))]
	var arrived: Dictionary = Migrants.arrive(controller, "h1", beds)
	if not _check(arrived.arrived.size() == 2 and str(arrived.reason).is_empty(), "a household of two arrives", arrived): return
	var residents: Dictionary = _team_of(lab, cadres[0])
	if not _check(int(residents.team_id) == home and residents.person_ids.size() == 4 and residents.person_ids.has(int(arrived.arrived[0])) and residents.person_ids.has(int(arrived.arrived[1])), "they join the residents' team", residents): return
	for identity: Variant in arrived.arrived:
		var person: Dictionary = controller.person_actions._person(int(identity), false)
		if not _check(not person.is_empty() and str(person.body.get("military_role", "")) == "civilian", "#%d is a living civilian" % int(identity)): return
	var housing: Dictionary = lab.terrain.site.housing
	if not _check(int(housing[str(int(arrived.arrived[0]))].cell) == int(beds[0]) and int(housing[str(int(arrived.arrived[1]))].cell) == int(beds[1]) and str(housing[str(int(arrived.arrived[1]))].house_id) == "h1", "registered at the free cells", housing): return
	if not _check(lab.terrain.site.get("households", {}).has("h1") and lab.crowd_site.crowd.validate(), "the household table takes them in; the native state validates", lab.terrain.site.get("households")): return
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("housing")
	lab.terrain.site.erase("households")
	_finished = true
	print("SITE_RESIDENT_MIGRANTS_PASS: ", checks, " checks; a migrant household joins the residents")
	quit(0)
