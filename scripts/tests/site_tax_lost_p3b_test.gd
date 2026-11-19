extends SceneTree
## 軍餉與稅收 P3b slice 3 (pay-and-tax plan §4.5; PT-17, PT-18's standing answer): a tax team beaten on the road, the
## ledger's faction mark and the settlement's answer. A 落草 world opens (the player's band stands here); a lawful
## faction 乙國 is founded and two cadres stand apart as its tax team, out on a round that has visited one fief. Checks:
## - while its people stand, the round goes on; with both dead, the sweep ends it: the route leaves the ledger, the
##   visited fief stays paid (its collection record is kept), the stop not reached owes nothing, the ledger validates;
##   the Site's Region evaluation sweeps the same way;
## - the faction mark: a faction that sent a tax team collects by tax teams (uses_teams), the mark validates and keeps
##   the field, a malformed mark is refused;
## - the answer: a finance record's tax_answer validates for pay / partial / refuse and nothing else; set_answer refuses
##   an unknown answer, a Site without a settlement record and a requester who is neither head nor 度支.
## Output: SITE_TAX_LOST_P3B_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const TaxEnvoy = preload("res://scripts/terrain_lab/site_tax_envoy.gd")
const TaxRoutes = preload("res://scripts/region_lab/region_tax_routes.gd")
const GameplayClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_TAX_LOST_P3B_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TAX_LOST_P3B OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _kill(lab: TerrainLab, person: int) -> bool:
	var index := int(lab.crowd_site._index_by_id.get(person, -1))
	return index >= 0 and bool(lab.crowd_site.set_soldier_fields(index, {"hp": 0.0}))

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "稅隊世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "bandit", "name": "老寨"}), "a 落草 world is requested", RegionEntry.menu_message): return
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
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 5, "the player's band has five cadres", cadres): return
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, cadres[4]), "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "乙國 is saved", prepared): return
	var lawful := int(prepared.faction_id)
	var scope := str(lab.terrain.site.id)
	var here: Dictionary = slot._coordinate(lab.terrain)
	var capital := Grid.site_id(str(slot.pin.atlas_id), here.site + Vector2i(2, 0))
	var visited := Grid.site_id(str(slot.pin.atlas_id), here.site + Vector2i(1, 0))
	var unreached := Grid.site_id(str(slot.pin.atlas_id), here.site + Vector2i(-1, 0))
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(cadres[0], lawful)
	if not _check(apart.ok and lab.crowd_site.join_team(cadres[1], int(apart.team_id), true).ok, "two cadres stand apart as 乙國's tax team", apart): return

	# PT-17.
	var ledger: Dictionary = slot.region_registry()
	var route := {"token": "tax_lost", "faction": lawful, "season": 3, "home_site": capital, "captain_ref": JoinFaction._world_ref(controller, cadres[0]),
		"envoy_ref": JoinFaction._world_ref(controller, cadres[1]), "stops": [visited, scope, unreached], "done": {visited: "full"}, "phase": "out", "day": 0, "carried": {"coin": 4}}
	var added := TaxRoutes.add(ledger, route)
	TaxRoutes.record_collection(ledger, lawful, visited, 3, 400, 400)
	if not _check(added.ok and TaxEnvoy.sweep_lost(slot, lab).is_empty() and TaxRoutes.routes(ledger).size() == 1, "while its people stand the round goes on", added): return
	if not _check(_kill(lab, cadres[0]) and _kill(lab, cadres[1]), "both of its people are dead"): return
	var swept: Array = TaxEnvoy.sweep_lost(slot, lab)
	if not _check(swept.size() == 1 and str(swept[0].at_site) == scope and TaxRoutes.routes(ledger).is_empty(), "the round ends where it was beaten", swept): return
	if not _check(int(TaxRoutes.collected_of(ledger, lawful, visited, 3).get("paid", -1)) == 400 and TaxRoutes.collected_of(ledger, lawful, unreached, 3).is_empty()
		and GameplayClock.validate_registry(ledger, float(slot.control.logical_game_seconds)).ok,
		"the visited fief stays paid; the stop not reached owes nothing; the ledger validates", ledger.get("tax_routes")): return
	var second := route.duplicate(true)
	second["token"] = "tax_lost_2"
	var lone: Dictionary = lab.crowd_site.detach_to_new_team(cadres[2], lawful)
	second["captain_ref"] = JoinFaction._world_ref(controller, cadres[2])
	if not _check(lone.ok and TaxRoutes.add(ledger, second).ok and _kill(lab, cadres[2]), "a second round's lone captain dies here", lone): return
	var evaluated: Dictionary = TaxEnvoy.evaluate(slot, lab)
	if not _check(evaluated.get("lost", []).size() == 1 and TaxRoutes.routes(ledger).is_empty(), "the Site's evaluation ends that round too", evaluated): return

	# The faction mark.
	if not _check(not TaxRoutes.uses_teams(ledger, lawful), "before any round of its own, a faction does not collect by tax teams"): return
	TaxRoutes.mark_faction(ledger, lawful)
	TaxRoutes.mark_faction(ledger, lawful)
	if not _check(TaxRoutes.uses_teams(ledger, lawful) and not TaxRoutes.uses_teams(ledger, lawful + 1) and ledger.tax_routes.factions == [lawful]
		and GameplayClock.validate_registry(ledger, float(slot.control.logical_game_seconds)).ok, "the mark is kept once and validates"): return
	var broken: Dictionary = ledger.duplicate(true)
	broken.tax_routes.factions = [-3]
	if not _check(not GameplayClock.validate_registry(broken, float(slot.control.logical_game_seconds)).ok, "a malformed mark is refused"): return

	# The answer.
	var ref := {"kind": "settlement", "site_id": scope, "org_id": "tax_village"}
	var record := Finance.empty_record(ref, 0)
	var key := Finance.org_key(ref)
	var answers_ok := true
	for answer: String in ["pay", "partial", "refuse"]:
		record["tax_answer"] = answer
		answers_ok = answers_ok and Finance.valid_record(key, record)
	record["tax_answer"] = "maybe"
	var bad_answer := Finance.valid_record(key, record)
	record.erase("tax_answer")
	if not _check(answers_ok and not bad_answer and Finance.valid_record(key, record), "tax_answer: pay, partial or refuse, or absent"): return
	if not _check(str(TaxEnvoy.set_answer(lab, player, "maybe").get("code", "")) == "INVALID" and str(TaxEnvoy.set_answer(lab, player, "refuse").get("code", "")) == "UNESTABLISHED",
		"set_answer refuses an unknown answer and a Site without a settlement"): return
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "tax_village", "center_id": "c", "level": 2, "name": "稅村", "owner_faction": lawful,
		"offices": SiteOffices.default_offices("settlement", cadres[3], true), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["finance"] = {key: Finance.empty_record(ref, 0)}
	var refused := TaxEnvoy.set_answer(lab, player, "refuse")
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("finance")
	if not _check(str(refused.get("code", "")) == "NO_AUTHORITY", "a requester who is neither head nor 度支 may not answer", refused): return
	_finished = true
	print("SITE_TAX_LOST_P3B_PASS: ", checks, " checks")
	quit(0)
