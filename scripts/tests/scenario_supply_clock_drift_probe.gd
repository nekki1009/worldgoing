extends SceneTree
## Probe (headless, diagnostic): how far each crowd team's supply clock (sustain.at) drifts from the Site clock
## ((minute + phase) * 60) while demo A runs idle at x16 from a 選現成人物 start (`-- --role=captain`). The strict save
## refuses a drift over 1e-5 s (供養時鐘超前 Site / 落後 Site). Prints every frame where a team's drift changes by more
## than `--threshold` s (default 1e-9; first 200), and a summary every game hour; stops after `--hours=N` game hours (default 24).
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

var _finished := false

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	create_timer(3300.0).timeout.connect(func() -> void: _done(1, "3300-second deadline"))
	_run.call_deferred()

func _done(code: int, message: String) -> void:
	if _finished: return
	_finished = true
	print("DRIFT_%s %s" % ["PASS" if code == 0 else "FAIL", message])
	TerrainArmy.release_contact_source()
	quit(code)

func _run() -> void:
	var role := _arg("role", "captain")
	var hours := int(_arg("hours", "24"))
	var person: Dictionary = {}
	for row: Dictionary in ScenarioPeople.people(PACKAGE).get("people", []):
		if str(row.role) == role:
			person = row
			break
	if person.is_empty() or not RegionEntry.request_new_world(person.site, {"name": str(person.name)}, "漂移", "", PACKAGE, {"mode": "neutral"}, {"surname": str(person.name).left(1)}, {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}, [], {"name": str(person.name)}):
		return _done(1, "refused")
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null: return _done(1, "not born")
	for _frame: int in range(5): await process_frame
	var controller: SiteController = lab.site_controller
	lab.simulation_speed = 16.0
	var last := {}
	var events := 0
	var threshold := float(_arg("threshold", "0.000000001"))
	var start_minute := int(lab.terrain.site.minute)
	var hour := start_minute / 60
	for frame: int in range(4000000):
		await process_frame
		if _finished: return
		var before_site := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
		lab._process(1.0 / 30.0)
		controller.person_actions.settle_after_contacts()
		var site_seconds := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
		for owner: RefCounted in lab.crowd_site.person_owners():
			var entry: Dictionary = controller._supply_entry(owner)
			if entry.is_empty() or not entry.get("sustain") is Dictionary: continue
			var key := str(owner.team_id) if "team_id" in owner else str(owner)
			var drift := float(entry.sustain.at) - site_seconds
			var prior := float(last.get(key, 0.0))
			if last.has(key) and absf(drift - prior) > threshold and events < 200:
				events += 1
				print("DRIFT frame %d team %s: %.9f -> %.9f (step %.9f s, Site %.6f -> %.6f, minute %d phase %.12f, cohorts %d)" % [frame, key, prior, drift, site_seconds - before_site, before_site, site_seconds, int(lab.terrain.site.minute), float(lab.terrain.site.phase), entry.sustain.cohorts.size()])
			last[key] = drift
		var now_hour := int(lab.terrain.site.minute) / 60
		if now_hour != hour:
			hour = now_hour
			var parts: Array[String] = []
			for key: Variant in last: parts.append("%s %.9f" % [str(key), float(last[key])])
			print("DRIFT hour %d (frame %d): %s" % [(int(lab.terrain.site.minute) - start_minute) / 60, frame, ", ".join(parts)])
			if (int(lab.terrain.site.minute) - start_minute) / 60 >= hours: break
	_done(0, "%d drift events" % events)
