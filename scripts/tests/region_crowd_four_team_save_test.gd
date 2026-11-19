extends SceneTree
## Option C roster containers: a crowd Site with more deployed teams than the Lab's three default TerrainArmy slots saves
## and loads. Before the fix a fourth team had no container, so the fire transport carried no command row for it and the
## Store refused the save (CORRUPT_FIRE_OWNER). Checks:
## - four teams deploy into one native crowd, and every team has a TerrainArmy container with its team id;
## - the Site saves (the Store accepts the fire owners), loads, and keeps all four teams native.
## Run only with: --crowd --crowd-test <fresh_run_id>
## Output: REGION_CROWD_FOUR_TEAM_SAVE_PASS on success; quit(1) on any failure.

var checks := 0
var lab: TerrainLab

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: _fail("240-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	printerr("REGION_CROWD_FOUR_TEAM_SAVE_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_CROWD_FOUR_TEAM_SAVE OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _side(count: int, faction: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side.faction = faction
	return side

## Every deployed (non-solo) crowd team has a TerrainArmy container whose team id matches.
func _containers_match(crowd: Variant, phase: String) -> bool:
	var deployed := 0
	for team: Dictionary in crowd.teams:
		if bool(team.get("solo", false)): continue
		deployed += 1
		var found := false
		for army: TerrainArmy in lab.combat_armies: found = found or army.team_id == int(team.team_id)
		if not _check(found, phase + ": the crowd team has its TerrainArmy container", team.team_id): return false
	return _check(deployed == 4, phase + ": four deployed crowd teams", deployed)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd") and args.has("--crowd-test"), "native startup and a fresh --crowd-test run id required"): return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "formal TerrainLab scene exists"): return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "formal TerrainLab instance exists"): return
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	if not _check(lab.character != null and lab.site_controller != null, "formal scene has its player body and Controller"): return
	lab.character.set_process(false)
	lab.site_controller._auto_save_blocked = true
	if not _check(lab.crowd_site != null and not lab.crowd_site.active, "formal scene has an inactive CrowdSite"): return
	if not _check(lab.combat_armies.size() == 3, "the Lab starts with its three default army slots", lab.combat_armies.size()): return
	var centre: Vector2i = lab.terrain.spawn_cell
	var cells: Array = []
	var sides: Array[Dictionary] = []
	for slot in range(4):
		var team_cells: Array[Vector2i] = [centre + Vector2i(-6 + slot * 4, 6), centre + Vector2i(-5 + slot * 4, 6)]
		cells.append(team_cells)
		sides.append(_side(team_cells.size(), slot + 1))
	var entered: Dictionary = lab.crowd_site.deploy(sides, cells)
	if not _check(entered.get("ok", false) and lab.crowd_site.active, "four teams deploy into one native crowd", entered): return
	if not _containers_match(lab.crowd_site, "deploy"): return

	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.get("ok", false) == true, "the four-team crowd Site saves (fire owners match the rosters)", saved): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.get("ok", false) == true and lab.crowd_site.active, "the four-team crowd Site loads", loaded): return
	if not _containers_match(lab.crowd_site, "load"): return

	lab.queue_free()
	await process_frame
	print("REGION_CROWD_FOUR_TEAM_SAVE_PASS: ", checks, " checks; every crowd team has a roster container, the four-team Site saves and loads")
	quit(0)
