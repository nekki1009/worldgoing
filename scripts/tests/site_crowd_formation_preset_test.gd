extends SceneTree
## Crowd formations (G7b follow-up): a team's preset survives size changes and saves. A world opens with a founded
## faction (the player captains his cadres). Checks:
## - the player sets "wedge": the native shape holds one slot per member and the preset is recorded on the Site;
## - a cadre leaves: the team is laid out as a wedge for its new size; he comes back: again for the full size;
## - the record passes the save rules (malformed records are refused); the Site saves and the native blob reloads;
## - "auto" clears the record.
## Output: SITE_CROWD_FORMATION_PRESET_PASS on success; quit(1) on any failure or the deadline.

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
	printerr("SITE_CROWD_FORMATION_PRESET_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CROWD_FORMATION_PRESET OK ", checks, ": ", message)
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

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "陣形世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	for _frame: int in range(10): await process_frame
	var controller: SiteController = lab.site_controller
	var player := int(lab.controlled_person_id())
	var team: Dictionary = _team_of(lab, player)
	var team_id := int(team.team_id)
	var formation := int(team.formation)
	var size: int = team.person_ids.size()
	if not _check(size >= 3, "the player's team has at least three people", size): return
	var set_wedge: Dictionary = lab.crowd_site.set_team_preset(team_id, "wedge", "player")
	if not _check(set_wedge.ok and int(lab.crowd_site.crowd.get_formation_shape(formation)) == size and lab.crowd_site.team_preset(team_id) == "wedge"
		and str(lab.terrain.site.get(lab.crowd_site.PRESET_SECTION, {}).get(str(team_id), "")) == "wedge", "the player sets a wedge: one slot per member, recorded on the Site", set_wedge): return
	var cadre := -1
	for person: Variant in team.person_ids:
		if int(person) != player and cadre < 0: cadre = int(person)
	for _frame: int in range(600):
		var owner: Variant = lab.crowd_site.person_owner(cadre)
		if owner != null and lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id[cadre])): break
		await process_frame
	var left: Dictionary = lab.crowd_site.detach_to_new_team(cadre, int(team.faction))
	if not _check(left.ok and int(lab.crowd_site.crowd.get_formation_shape(formation)) == size - 1 and lab.crowd_site.team_preset(team_id) == "wedge", "a cadre leaves: still a wedge, for the smaller team", [left, lab.crowd_site.crowd.get_formation_shape(formation)]): return
	var back: Dictionary = lab.crowd_site.join_team(cadre, team_id)
	if not _check(back.ok and int(lab.crowd_site.crowd.get_formation_shape(formation)) == size, "he comes back: a wedge for the full team", [back, lab.crowd_site.crowd.get_formation_shape(formation)]): return
	var Crowd: Script = load("res://scripts/terrain_lab/crowd_site.gd")
	if not _check(Crowd.call("validate_presets", lab.terrain.site).ok, "the record passes the save rules"): return
	for bad: Variant in [[], {"x": "wedge"}, {"1": "auto"}, {"1": "spiral"}, {"1": 3}]:
		if not _check(not Crowd.call("validate_presets", {Crowd.PRESET_SECTION: bad}).ok, "a malformed record is refused", bad): return
	var saved: Dictionary = controller._commit_diplomacy({"ok": true, "registry": controller.region_slot.control.faction_registry}, "")
	if not _check(saved.ok and _blob_loads(lab), "the Site saves and the native blob reloads", saved): return
	var cleared: Dictionary = lab.crowd_site.set_team_preset(team_id, "auto", "player")
	if not _check(cleared.ok and not lab.terrain.site.has(Crowd.PRESET_SECTION) and lab.crowd_site.team_preset(team_id) == "auto", "auto clears the record", cleared): return
	_finished = true
	print("SITE_CROWD_FORMATION_PRESET_PASS: ", checks, " checks; crowd presets follow size changes and save")
	quit(0)
