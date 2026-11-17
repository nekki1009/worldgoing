extends SceneTree
## 平民 C4c-1: a new person is born into a team on a live crowd Site (CrowdSite.add_new_person). A world opens with a
## founded faction (the player captains his cadres). Checks:
## - a refusal (a used person id, an unknown team) changes nothing;
## - the world allocator issues a new id; the person joins the player's team as a civilian at the given cell: native
##   soldier, roster row, team list, owner and supply cohort agree, the native state validates;
## - the Site saves through a Region checkpoint and the native blob reloads; a second new person joins after him.
## Output: SITE_CROWD_NEW_PERSON_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_CROWD_NEW_PERSON_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CROWD_NEW_PERSON OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _team_of(lab: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

func _blob_loads(lab: TerrainLab) -> bool:
	var native_save: Dictionary = lab.crowd_site.capture_save(true)
	if not native_save.get("ok", false): return false
	var native: Object = ClassDB.instantiate("ArmyCrowd")
	native.call("setup", 1, int(lab.terrain.seed_value))
	return bool(native.call("load_state", Marshalls.base64_to_raw(str(native_save.section.get("blob", "")))))

func _new_row(lab: TerrainLab, template: Dictionary, identity: int) -> Dictionary:
	var row: Dictionary = template.duplicate(true)
	for field: String in ["social", "social_state", "vital", "reputation", "combat_record", "work_task", "family"]: row.erase(field)
	row["person_id"] = identity
	row["name"] = "流民%d" % identity
	row["hp"] = 100.0
	row["cargo"] = {}
	row["item_state"] = SiteRuntime.new_item_state("person:%d" % identity)
	row["military_role"] = "civilian"
	return row

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "新人物世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var team: Dictionary = _team_of(lab, player)
	var team_id := int(team.team_id)
	var template_id := int(team.person_ids.filter(func(p: Variant) -> bool: return int(p) != player)[0])
	var template: Dictionary = lab.crowd_site.native_roster(team_id).units.filter(func(r: Dictionary) -> bool: return int(r.person_id) == template_id)[0]
	var size_before: int = team.person_ids.size()
	var at := Vector2(lab.crowd_site.combat_target(player).cell) + Vector2(1.5, 0.5)

	var used: Dictionary = lab.crowd_site.add_new_person(team_id, _new_row(lab, template, template_id), at)
	var unknown: Dictionary = lab.crowd_site.add_new_person(999999, _new_row(lab, template, 987654), at)
	if not _check(not used.ok and not unknown.ok and _team_of(lab, player).person_ids.size() == size_before, "a used id or an unknown team is refused and changes nothing", [used, unknown]): return

	var ids: Array[int] = lab._allocate_army_person_ids(1)
	if not _check(ids.size() == 1 and ids[0] > 0, "the world allocator issues a new id", ids): return
	var born: Dictionary = lab.crowd_site.add_new_person(team_id, _new_row(lab, template, ids[0]), at)
	if not _check(born.ok, "the new person joins the team", born): return
	var newcomer := ids[0]
	var person: Dictionary = controller.person_actions._person(newcomer, false)
	if not _check(not person.is_empty() and float(person.hp) > 0.0 and _team_of(lab, newcomer).team_id == team_id and _team_of(lab, player).person_ids.size() == size_before + 1, "he is a living member of the team", person.keys()): return
	if not _check(str(person.body.get("military_role", "")) == "civilian" and lab.crowd_site.crowd.validate(), "a civilian; the native state validates"): return
	var supply: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(team_id), {})
	if not supply.is_empty():
		var held := false
		for cohort: Dictionary in supply.get("sustain", {}).get("cohorts", []):
			if cohort.ids.has(newcomer): held = true
		if not _check(held, "the team's supply takes him in", supply.get("sustain", {}).get("cohorts")): return
	var saved: Dictionary = controller._commit_diplomacy({"ok": true, "registry": controller.region_slot.control.faction_registry}, "")
	if not _check(saved.ok and _blob_loads(lab), "the Site saves and the native blob reloads", saved): return
	var more: Array[int] = lab._allocate_army_person_ids(1)
	var second: Dictionary = lab.crowd_site.add_new_person(team_id, _new_row(lab, template, more[0]), at + Vector2(1.0, 0.0))
	if not _check(second.ok and _team_of(lab, player).person_ids.size() == size_before + 2 and _blob_loads(lab), "a second new person joins after him", second): return
	_finished = true
	print("SITE_CROWD_NEW_PERSON_PASS: ", checks, " checks; a new person joins a live crowd team")
	quit(0)
