extends SceneTree
## Probe (diagnostic): after a 選現成人物 birth of demo A (`--role=`, `--index=`), every crowd team's holder offices are
## checked as SiteDutyAI.review_crowd_personnel reads them (team_offices(true), SiteOffices.validate team, no stored head
## holder); then the world runs at x16 and the check repeats every game hour for `--hours=N` (default 30). Prints each
## invalid record once with its team. A team_offices(true) of {} made review_crowd_personnel fail on `.duty_ai`
## (found 2026-11-28, leader index 3, day 1).
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

var _reported := {}

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	create_timer(3000.0).timeout.connect(func() -> void: print("OFFICES_PROBE deadline"); quit(1))
	_run.call_deferred()

func _check(lab: TerrainLab, when: String) -> void:
	var crowd: Variant = lab.crowd_site
	for owner: Variant in lab.team_owners():
		if not is_instance_valid(owner) or not owner.has_army(): continue
		var team_id := int(owner.team_id)
		var holder: Variant = crowd.team_holder(team_id)
		if holder == null: continue
		crowd.project_team_holder(holder)
		var read: Dictionary = holder.team_offices(true)
		if read.has("duty_ai"): continue
		var key := "%d:%s" % [team_id, JSON.stringify(holder.offices).sha256_text()]
		if _reported.has(key): continue
		_reported[key] = true
		print("OFFICES_PROBE invalid %s team %d (faction %d, %d members, formal commander %d): %s" % [when, team_id, int(owner.faction_id) if "faction_id" in owner else -1,
			owner.records.size() if "records" in owner else -1, int(holder.formal_commander), JSON.stringify(holder.offices).left(2500)])

func _run() -> void:
	var role := _arg("role", "leader")
	var skip := int(_arg("index", "0"))
	var person: Dictionary = {}
	for row: Dictionary in ScenarioPeople.people(PACKAGE).get("people", []):
		if str(row.role) != role: continue
		if skip > 0:
			skip -= 1
			continue
		person = row
		break
	if person.is_empty() or not RegionEntry.request_new_world(person.site, {"name": str(person.name)}, "職位", "", PACKAGE, {"mode": "neutral"}, {"surname": str(person.name).left(1)}, {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}, [], {"name": str(person.name)}):
		print("OFFICES_PROBE refused")
		quit(1)
		return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		print("OFFICES_PROBE not born")
		quit(1)
		return
	for _frame: int in range(5): await process_frame
	print("OFFICES_PROBE born as %s %s at %s" % [role, str(person.name), str(person.site)])
	_check(lab, "at birth")
	lab.simulation_speed = 16.0
	var start := int(lab.terrain.site.minute)
	var hour := start / 60
	var hours := int(_arg("hours", "30"))
	for frame: int in range(2000000):
		await process_frame
		lab._process(1.0 / 30.0)
		lab.site_controller.person_actions.settle_after_contacts()
		if int(lab.terrain.site.minute) / 60 == hour: continue
		hour = int(lab.terrain.site.minute) / 60
		_check(lab, "hour %d" % ((int(lab.terrain.site.minute) - start) / 60))
		if (int(lab.terrain.site.minute) - start) / 60 >= hours: break
	print("OFFICES_PROBE done, %d invalid records" % _reported.size())
	TerrainArmy.release_contact_source()
	await process_frame
	quit(0)
