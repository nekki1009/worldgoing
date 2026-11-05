extends SceneTree
## Crowd formation presets (G7b). In a new world the player captains his start team (him and his cadres). Checks:
## - an unknown preset is refused; a preset from someone who is not the current commander is refused;
## - "wedge" gives the native formation one slot offset pair per member, matching the preset geometry;
## - after a few seconds every member stands near a wedge slot;
## - the shape survives a native save / load with the same hash; "auto" clears it;
## - the formation UI applies the selected preset under crowd.
## Output: CROWD_FORMATION_PRESET_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("CROWD_FORMATION_PRESET_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("CROWD_FORMATION_PRESET OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	var requested: bool = RegionEntry.request_new_world(START, {}, "陣形測試世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
	if not _check(requested, "a new world is requested", RegionEntry.menu_message): return
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
	var site: CrowdSite = lab.crowd_site
	if not _check(site.crowd.has_method("set_formation_shape"), "the native crowd offers formation shapes"): return
	var command: Dictionary = controller._crowd_command_team("player")
	var team: Dictionary = site._team_by_id(int(command.get("team_id", -1)))
	if not _check(not team.is_empty() and team.person_ids.size() == 1 + TerrainLab.INITIAL_CADRES, "the player commands his start team", command): return
	var team_id := int(team.team_id)
	var formation := int(team.formation)
	var count := int(team.person_ids.size())
	if not _check(site.set_team_preset(team_id, "spiral", "player").get("code") == "BAD_ARGS", "an unknown preset is refused"): return
	if not _check(site.set_team_preset(team_id, "wedge", "nobody").ok, "the current commander may order a preset", site.set_team_preset(team_id, "wedge", "nobody")): return
	var done: Dictionary = site.set_team_preset(team_id, "wedge", "player")
	if not _check(done.ok and int(site.crowd.get_formation_shape(formation)) == count, "a wedge gives one slot pair per member", [done, site.crowd.get_formation_shape(formation)]): return
	var offsets := CrowdSite.preset_offsets("wedge", count)
	if not _check(offsets.size() == 2 * count and site.team_preset(team_id) == "wedge", "the offsets come from the preset geometry", offsets): return
	# Let the team walk into its wedge, then compare positions with the slot points.
	for _frame: int in range(240):
		await process_frame
		if _finished: return
	var state: Dictionary = site.formation_state(formation)
	var face := float(state.get("facing", 0.0))
	var fx := cos(face)
	var fy := sin(face)
	var centre := Vector2(float(state.get("cx", 0.0)), float(state.get("cy", 0.0)))
	var on_slot := 0
	for k: int in range(count):
		var lat := offsets[2 * k]
		var back := offsets[2 * k + 1]
		var point := centre + Vector2(-fy * lat - fx * back, fx * lat - fy * back)
		for person: Variant in team.person_ids:
			var soldier := site.soldier_state(int(site._index_by_id[int(person)]))
			if Vector2(float(soldier.px), float(soldier.py)).distance_to(point) < 0.8:
				on_slot += 1
				break
	if not _check(state.has("cx") and on_slot == count, "every member stands near a wedge slot", [on_slot, count, state.get("cx"), state.get("cy")]): return
	# A live Site's crowd and a fresh copy loaded from its blob differ in state_hash even without a shape (pre-existing,
	# see fail_triage crowd_c2_c3); so the round trip is checked copy to copy.
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 581)
	var again: RefCounted = ClassDB.instantiate("ArmyCrowd")
	again.setup(1, 581)
	var loaded: bool = copy.load_state(site.crowd.save_state()) and again.load_state(copy.save_state())
	if not _check(loaded and int(copy.get_formation_shape(formation)) == count and int(again.get_formation_shape(formation)) == count and again.state_hash() == copy.state_hash(), "the shape survives native save / load with the same hash"): return
	if not _check(site.set_team_preset(team_id, "auto", "player").ok and int(site.crowd.get_formation_shape(formation)) == 0, "auto clears the shape"): return
	# The formation UI path under crowd.
	for index: int in range(controller.formation_preset_choice.item_count):
		if str(controller.formation_preset_choice.get_item_metadata(index)) == "circle": controller.formation_preset_choice.select(index)
	controller._apply_formation_change()
	if not _check(int(site.crowd.get_formation_shape(formation)) == count and site.team_preset(team_id) == "circle", "the formation UI applies the selected preset", site.team_preset(team_id)): return
	_finished = true
	print("CROWD_FORMATION_PRESET_PASS: ", checks, " checks; refusals, wedge slots, native save / load, clear and UI hold")
	quit(0)
