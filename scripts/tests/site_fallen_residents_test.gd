extends SceneTree
## 平民 C5 (reports/civilian-site-behavior-plan.md §4.7): residents of a fallen settlement submit or leave. A world opens
## with a founded faction 甲 (the player captains his cadres). Four cadres become residents of a second faction 乙 in one
## captainless team; then 乙's settlement (a test-only stand-in, never saved) falls to 甲 and the record of their old homes
## is written as SiteSettlement.fall_to writes it. Checks:
## - remember writes {from, to, minute, people} and passes the save rules; malformed records are refused;
## - day 1: the two with G < 40 submit: 甲, one captainless team, registered again at their old door cells; the one at
##   G >= 60 leaves (his household onto the Region map); the one at G 50 waits;
## - day 30: the one still waiting leaves; the record ends.
## Output: SITE_FALLEN_RESIDENTS_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Fallen = preload("res://scripts/terrain_lab/site_fallen_residents.gd")
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
	printerr("SITE_FALLEN_RESIDENTS_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FALLEN_RESIDENTS OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}


func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "陷落原居民世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var conqueror := int(_team_of(lab, player).faction)
	var cadres: Array[int] = []
	for person: Variant in _team_of(lab, player).person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 4, "the player has four cadres", cadres): return
	var residents: Array[int] = cadres.slice(0, 4)
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": "乙國", "kind": "npc", "leader_ref": JoinFaction._world_ref(controller, residents[0]), "founded_at": float(slot.control.logical_game_seconds)})
	if not _check(prepared.ok and controller._commit_diplomacy(prepared, "").ok, "faction 乙 is saved", prepared): return
	var defender := int(prepared.faction_id)
	var first: Dictionary = lab.crowd_site.detach_to_new_team(residents[0], defender)
	if not _check(first.ok, "the first resident stands apart as 乙", first): return
	for person: int in residents.slice(1):
		var moved: Dictionary = lab.crowd_site.join_team(person, int(first.team_id), true)
		if not _check(moved.ok, "#%d joins the residents (straight across, taking 乙's faction)" % person, moved): return
	if not _check(lab.crowd_site.clear_captain(int(first.team_id)).ok and int(lab.crowd_site.formation_state(int(_team_of(lab, residents[0]).formation)).get("current_person", -2)) == -1, "the residents' team is captainless"): return
	for person: int in residents:
		if not _check(lab.crowd_site.native_set_military_role(person, "civilian").ok, "#%d is a civilian" % person): return

	# The fall, as SiteSettlement.fall_to writes it, over a stand-in settlement now owned by 甲.
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "fallen_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": conqueror,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	var old := {}
	for index: int in residents.size(): old[str(residents[index])] = {"version": 1, "house_id": "h%d" % (index / 2), "cell": index}
	Fallen.remember(lab.terrain, defender, conqueror, old)
	var record: Dictionary = lab.terrain.site.get(Fallen.SECTION, {})
	if not _check(int(record.get("from", -1)) == defender and int(record.to) == conqueror and record.people.size() == 4 and Fallen.validate(lab.terrain.site).ok, "the fall remembers their old homes", record): return
	for bad: Variant in [{"from": 1, "to": 2, "minute": 0}, {"from": 1, "to": 2, "minute": 0, "people": {"x": ["h", 0]}}, {"from": 1, "to": 2, "minute": 0, "people": {"1": ["h"]}}]:
		if not _check(not Fallen.validate({Fallen.SECTION: bad}).ok, "a malformed record is refused", bad): return
	var ref := ProduceTax.settlement_ref(lab.terrain)
	var set_g := func(index: int, value: int) -> void:
		SiteSocial.relation(SiteSocial.state_of(controller.person_actions._person(residents[index], false).body), ref).G = value
	for index: int in residents.size(): set_g.call(index, [50, 50, 70, 50][index])

	# Day 1: the one at G >= 60 leaves (his household onto the Region map); the others wait.
	var today := int(float(record.minute) / 1440.0) + 1
	# Judged against the stand-in settlement; carried out after it is gone (a dispatch saves the Site).
	var settlement_stand_in: Dictionary = lab.terrain.site.settlement
	var first_verdict := Fallen.judge(controller, today)
	lab.terrain.site.erase("settlement")
	var first_day := Fallen.apply(controller, first_verdict)
	lab.terrain.site["settlement"] = settlement_stand_in
	if not _check(first_day.left == [residents[2]] and first_day.waiting == [residents[0], residents[1], residents[3]] and first_day.submitted.is_empty() and first_day.failed.is_empty(), "day 1: one leaves, three wait", first_day): return
	if not _check(_team_of(lab, residents[2]).is_empty(), "the one who left is gone from the Site"): return
	# Day 2: two fall below 40 and submit.
	set_g.call(0, 10)
	set_g.call(1, 20)
	var second_day := Fallen.apply(controller, Fallen.judge(controller, today + 1))
	if not _check(second_day.submitted == [residents[0], residents[1]] and second_day.waiting == [residents[3]] and second_day.failed.is_empty(), "day 2: two submit, one waits", second_day): return
	var settled: Dictionary = _team_of(lab, residents[0])
	if not _check(int(settled.faction) == conqueror and settled.person_ids.has(residents[1]) and settled.person_ids.size() == 2 and int(lab.crowd_site.formation_state(int(settled.formation)).get("current_person", -2)) == -1, "the submitters are one captainless team of 甲", settled): return
	var housing: Dictionary = lab.terrain.site.get("housing", {})
	if not _check(str(housing.get(str(residents[0]), {}).get("house_id", "")) == "h0" and int(housing[str(residents[1])].cell) == 1, "they are registered at their old door cells", housing): return
	var lone: Dictionary = _team_of(lab, residents[3])
	if not _check(lone.person_ids.size() == 1 and int(lab.crowd_site.formation_state(int(lone.formation)).get("formal_person", -2)) == residents[3], "the last one left in the old residents' team captains it (no leaderless solo)", lone): return
	# The stand-in houses do not exist: their registrations go before anything saves again.
	lab.terrain.site.erase("housing")
	var last_verdict := Fallen.judge(controller, today + Fallen.WINDOW_DAYS)
	lab.terrain.site.erase("settlement")
	var later := Fallen.apply(controller, last_verdict)
	if not _check(later.left == [residents[3]] and not lab.terrain.site.has(Fallen.SECTION) and later.failed.is_empty(), "after 30 days the one still waiting leaves; the record ends", later): return
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("housing")
	_finished = true
	print("SITE_FALLEN_RESIDENTS_PASS: ", checks, " checks; after a fall residents submit or leave")
	quit(0)
