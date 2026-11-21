extends SceneTree
## CIV-A4 平民裝 (Nekki 2026-11-20 A) on a real crowd Site, GPU (visual). Fixture: a cadre with his kit becomes a
## civilian resident and two unarmed newcomers join him as migrants do (his row, an empty holder). Checks:
## - the daily dressing (SiteController.dress_residents) puts both in the civilian look of their body, through the
##   crowd's equipment path: each now has a civilian kit with the four work tracks (was the soldier look before);
## - the schedule switches their work clip on the real CrowdSite: at wake both fetch water, and the native presentation
##   takes the set; asleep, nothing plays; a meal away from a real house plays nothing;
## - the dressed look survives the Site save rules (save_to);
## - an equipped civilian is not dressed (his gear look stays); dressing again changes nothing.
## Output: SITE_CIVILIAN_DRESS_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Dress = preload("res://scripts/terrain_lab/civilian_dress.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_CIVILIAN_DRESS_VISUAL_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVILIAN_DRESS_VISUAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## The first minute of the day in `phase` for a resident of diligence 50.
func _minute_of(phase: String) -> int:
	for minute: int in range(1440):
		if Schedule.phase_at(minute, 50) == phase: return minute
	return -1

func _civilian_kit(lab: TerrainLab, person: int) -> bool:
	var index := int(lab.crowd_site._index_by_id.get(person, -1))
	if index < 0 or index >= lab.crowd_site._kit_ids.size(): return false
	var kit := int(lab.crowd_site._kit_ids[index])
	return kit >= 0 and lab.crowd_site._civilian_activity._tracks.has(kit)

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU required"): return
	if not _check(RegionEntry.request_new_world(START, {}, "平民裝世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(1200):
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
	var defenders: Dictionary = _team_of(lab, player)
	var own := int(defenders.faction)
	var cadres: Array[int] = []
	for person: Variant in defenders.person_ids:
		if int(person) != player: cadres.append(int(person))
	cadres.sort()
	if not _check(cadres.size() >= 1, "the player has a cadre", cadres): return
	# The armed cadre becomes a civilian resident with his kit; two unarmed newcomers join him as the migrants do
	# (SiteResidentMigrants: his row, their own id and an empty holder).
	var armed := cadres[0]
	var apart: Dictionary = lab.crowd_site.detach_to_new_team(armed, own)
	if not _check(apart.ok and lab.crowd_site.native_set_military_role(armed, "civilian").ok, "the armed cadre stands apart as a civilian", apart): return
	var template: Dictionary = {}
	for row: Dictionary in lab.crowd_site.native_roster(int(apart.team_id)).get("units", []):
		if int(row.person_id) == armed: template = row
	var ids: Array[int] = lab._allocate_army_person_ids(2)
	var at: Dictionary = lab.crowd_site.soldier_state(int(lab.crowd_site._index_by_id[armed]))
	for index: int in ids.size():
		var row: Dictionary = template.duplicate(true)
		for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family"]: row.erase(field)
		row["person_id"] = ids[index]
		row["name"] = "居民%d" % ids[index]
		row["hp"] = 100.0
		row["cargo"] = {}
		row["item_state"] = SiteRuntime.new_item_state("person:%d" % ids[index])
		row["military_role"] = "civilian"
		var born: Dictionary = lab.crowd_site.add_new_person(int(apart.team_id), row, Vector2(float(at.px) + 1.0 + index, float(at.py)))
		if not _check(born.ok, "resident %d is born unarmed" % ids[index], born): return
	var first := ids[0]
	var second := ids[1]
	lab.terrain.site["settlement"] = {"version": 1, "settlement_id": "dress_village", "center_id": "c", "level": 2, "name": "測試村", "owner_faction": own,
		"offices": SiteOffices.default_offices("settlement", player, false), "fall_record": SiteSettlement.empty_fall_record()}
	lab.terrain.site["housing"] = {str(first): {"version": 1, "house_id": "h1", "cell": 0}, str(second): {"version": 1, "house_id": "h1", "cell": 1}, str(armed): {"version": 1, "house_id": "h1", "cell": 2}}
	for _frame: int in range(3): await process_frame
	if not _check(not _civilian_kit(lab, first) and not Dress.is_dressed(lab.crowd_site._records[first].appearance), "before dressing the resident has the soldier look"): return
	var dressed: Dictionary = controller.dress_residents()
	for _frame: int in range(3): await process_frame
	if not _check(int(dressed.dressed) == 2 and dressed.refused.is_empty(), "the dressing dresses the two unarmed civilians", dressed): return
	for person: int in [first, second]:
		if not _check(Dress.is_dressed(lab.crowd_site._records[person].appearance) and not Dress.is_hatted(lab.crowd_site._records[person].appearance) and _civilian_kit(lab, person),
			"resident %d wears the civilian look, without the hat (no outdoor job), on a civilian kit with work tracks" % person, lab.crowd_site._records[person].appearance): return
	if not _check(not Dress.is_dressed(lab.crowd_site._records[armed].appearance), "the equipped civilian keeps his gear look"): return
	if not _check(int(controller.dress_residents().dressed) == 0, "dressing again changes nothing"): return
	# The schedule on the real CrowdSite.
	var activity: Variant = lab.crowd_site._civilian_activity
	var day_start := Calendar.day_start_minute(int(Calendar.day_index(float(lab.terrain.site.minute))) + 1)
	lab.terrain.site.minute = day_start + _minute_of("wake")
	activity._decide(lab.crowd_site)
	if not _check(str(activity._choice.get(first, {}).get("clip", "")) == "civilian_fetch_water" and str(activity._choice.get(second, {}).get("clip", "")) == "civilian_fetch_water", "at wake both fetch water", activity._choice): return
	activity._since_update = INF
	activity._since_decide = 0.0
	activity.update(lab.crowd_site, 0.0)
	if not _check(not bool(activity._rejected) and activity._choice.size() == 2, "the native presentation takes the set", activity._choice): return
	lab.terrain.site.minute = day_start + _minute_of("sleep")
	activity._decide(lab.crowd_site)
	if not _check(activity._choice.is_empty(), "asleep, nothing plays", activity._choice): return
	lab.terrain.site.minute = day_start + _minute_of("meal")
	activity._decide(lab.crowd_site)
	if not _check(activity._choice.is_empty(), "a meal away from a real house plays nothing", activity._choice): return
	# The fixture's housing names no real house, which the save rules refuse; take it out, keep the dressed looks.
	lab.terrain.site.erase("settlement")
	lab.terrain.site.erase("housing")
	var synced: Dictionary = lab.crowd_site.sync_to_site()
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(synced.get("ok", true) and saved.ok and Dress.is_dressed(lab.crowd_site._records[first].appearance), "the dressed looks pass the Site save rules", [synced, saved]): return
	_finished = true
	print("SITE_CIVILIAN_DRESS_VISUAL_PASS: ", checks, " checks")
	quit(0)
