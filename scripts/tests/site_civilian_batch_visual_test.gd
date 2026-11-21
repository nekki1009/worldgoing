extends SceneTree
## CIV-A4 / CA-05 (output/civilian_atlas_plan_20261119/PLAN.md; Nekki 2026-11-20 A), reduced: a hundred residents on a
## real crowd Site, GPU (visual). A hundred unarmed civilians join the player's team as migrants do (a cadre's row, an
## empty holder) and are registered as residents. Checks:
## - the daily dressing dresses all hundred; every one has a civilian kit with the work tracks (unatlased none);
## - dressing adds no per-person Sprite2D, Skeleton3D or MeshInstance3D node (they stay in the native batch);
## - at wake the hundred fetch water and the native presentation takes the whole set;
## - in a work phase two of them, handed to the team's work by its commander, lift (standing) and the rest play nothing;
## - asleep, nothing plays.
## Real houses, farms and the household work path are left to the full CA-05.
## Output: SITE_CIVILIAN_BATCH_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Dress = preload("res://scripts/terrain_lab/civilian_dress.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const START := Vector2i(1170, 13252)
const PEOPLE := 100

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	printerr("SITE_CIVILIAN_BATCH_VISUAL_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVILIAN_BATCH_VISUAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _minute_of(phase: String) -> int:
	for minute: int in range(1440):
		if Schedule.phase_at(minute, 50) == phase: return minute
	return -1

func _count_nodes(node: Node) -> int:
	var count := 1 if node is Sprite2D or node is Skeleton3D or node is MeshInstance3D else 0
	for child: Node in node.get_children(): count += _count_nodes(child)
	return count

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU required"): return
	if not _check(RegionEntry.request_new_world(START, {}, "平民百人世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var crowd: Variant = lab.crowd_site
	var player := int(lab.controlled_person_id())
	var team: Dictionary = {}
	for row_team: Dictionary in crowd.teams:
		if not bool(row_team.get("departed", false)) and row_team.get("person_ids", []).has(player): team = row_team
	var template: Dictionary = {}
	for row: Dictionary in crowd.native_roster(int(team.team_id)).get("units", []):
		if int(row.person_id) != player: template = row
	if not _check(not template.is_empty(), "the player's team has a cadre row to copy"): return
	var at: Dictionary = crowd.soldier_state(int(crowd._index_by_id[player]))
	var ids: Array[int] = lab._allocate_army_person_ids(PEOPLE)
	if not _check(ids.size() == PEOPLE, "a hundred ids", ids.size()): return
	var housing := {}
	var born: Array[int] = []
	for index: int in ids.size():
		var row: Dictionary = template.duplicate(true)
		for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family", "skills"]: row.erase(field)
		row["person_id"] = ids[index]
		row["name"] = "居民%d" % ids[index]
		row["hp"] = 100.0
		row["cargo"] = {}
		row["item_state"] = SiteRuntime.new_item_state("person:%d" % ids[index])
		row["military_role"] = "civilian"
		var offset := Vector2(float(index % 10) - 4.5, float(index / 10) + 2.0)
		var made: Dictionary = crowd.add_new_person(int(team.team_id), row, Vector2(float(at.px), float(at.py)) + offset)
		if not made.ok: continue
		born.append(ids[index])
		housing[str(ids[index])] = {"version": 1, "house_id": "h%d" % (index / 4), "cell": index}
	if not _check(born.size() == PEOPLE, "a hundred civilians are born unarmed", born.size()): return
	lab.terrain.site["housing"] = housing
	for _frame: int in range(3): await process_frame
	var nodes_before := _count_nodes(root)
	var dressed: Dictionary = controller.dress_residents()
	for _frame: int in range(5): await process_frame
	if not _check(int(dressed.dressed) == PEOPLE and dressed.refused.is_empty(), "the dressing dresses all hundred", dressed): return
	var unatlased: Array = []
	for person: int in born:
		var index := int(crowd._index_by_id.get(person, -1))
		var kit := int(crowd._kit_ids[index]) if index >= 0 and index < crowd._kit_ids.size() else -1
		if not Dress.is_dressed(crowd._records[person].appearance) or kit < 0 or not crowd._civilian_activity._tracks.has(kit): unatlased.append(person)
	if not _check(unatlased.is_empty(), "every one has a civilian kit with the work tracks (unatlased none)", unatlased): return
	if not _check(_count_nodes(root) == nodes_before, "dressing adds no per-person Sprite2D, Skeleton3D or MeshInstance3D node", [nodes_before, _count_nodes(root)]): return
	var activity: Variant = crowd._civilian_activity
	var day_start := Calendar.day_start_minute(int(Calendar.day_index(float(lab.terrain.site.minute))) + 1)
	lab.terrain.site.minute = day_start + _minute_of("wake")
	activity._decide(crowd)
	var fetching := born.filter(func(person: int) -> bool: return str(activity._choice.get(person, {}).get("clip", "")) == "civilian_fetch_water")
	if not _check(fetching.size() == PEOPLE, "at wake the hundred fetch water", fetching.size()): return
	activity._since_update = INF
	activity._since_decide = 0.0
	activity.update(crowd, 0.0)
	if not _check(not bool(activity._rejected) and activity._choice.size() == PEOPLE, "the native presentation takes the whole set", activity._choice.size()): return
	# Two handed to the team's work by its commander (the player).
	var owner: Variant = crowd.person_owner(born[0])
	var workers: Array[int] = [born[0], born[1]]
	var assigned: Dictionary = {}
	for _frame: int in range(600): # newcomers may still be walking to their formation slots
		assigned = controller.work_team.assign(owner, workers, player)
		if assigned.ok or str(assigned.get("code", "")) != "BUSY": break
		await process_frame
	if not _check(assigned.ok and controller.work_team.is_assigned(born[0]) and controller.work_team.is_assigned(born[1]), "two are handed to the team's work", assigned): return
	lab.terrain.site.minute = day_start + _minute_of("work")
	activity._decide(crowd)
	var clips: Array = workers.map(func(person: int) -> String: return str(activity._choice.get(person, {}).get("clip", "")))
	if not _check(clips.all(func(clip: String) -> bool: return clip in ["civilian_lift", "civilian_carry"]) and activity._choice.size() == 2, "at work the two lift or carry, the rest play nothing", [clips, activity._choice.size()]): return
	activity._since_update = INF
	activity.update(crowd, 0.0)
	if not _check(not bool(activity._rejected), "the native presentation takes the work set"): return
	lab.terrain.site.minute = day_start + _minute_of("sleep")
	activity._decide(crowd)
	if not _check(activity._choice.is_empty(), "asleep, nothing plays", activity._choice.size()): return
	lab.terrain.site.erase("housing")
	_finished = true
	print("SITE_CIVILIAN_BATCH_VISUAL_PASS: ", checks, " checks")
	quit(0)
