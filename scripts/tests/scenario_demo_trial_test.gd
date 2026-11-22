extends SceneTree
## 示範劇本 A step 4: a small trial of the generator on the real Taiwan source (default -- --settlements=6 --bands=3
## --towns=1), born through the real boot path. Checks:
## - the generator builds and exports the package; the loader reads it (Sites, scenario); the menu's scenario list finds it;
## - the world is born (timed) and opens on the start Site; every faction of the scenario is in the registry with its
##   name and kind, every band has a chief, every settlement faction's main head leads it;
## - every settlement Site's first generation has its residents housed, its militia team, its head, its stocked
##   warehouse; every lair Site has its band team;
## - the world saves (timed).
## Prints SCENARIO_TRIAL_TIMES generate=… birth=… save=… and SCENARIO_TRIAL_PASS; quit(1) on any failure or the deadline.
## -- --package=<path> skips the generator and births the built package there (step 5: build_demo_a.gd builds
## res://assets/scenarios/demo_a/demo_a.json in about 16 minutes); --settlements/--bands/--towns must then match it.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _fail("1500-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("SCENARIO_TRIAL_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SCENARIO_TRIAL OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _arg(name: String, fallback: int) -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return int(argument.get_slice("=", 1))
	return fallback

func _text_arg(name: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return ""

## A built package's generator summary, read from the package itself: the start, the settlement Sites (each has its
## office row), the lair Sites, the residents of the settlements' authored states, the band members.
func _built_from(path: String) -> Dictionary:
	var package := RegionData.new()
	if not package.load_manifest(path).get("ok", false): return {"ok": false, "path": path}
	var scenario: Dictionary = package.author_scenario()
	var start: Array = package.author_initial_context().starting_site
	var settlements: Array = []
	var residents := 0
	for row: Dictionary in scenario.get("offices", []):
		var site := Vector2i(int(row.site[0]), int(row.site[1]))
		settlements.append(site)
		residents += package._author_initial.get("%d:%d" % [site.x, site.y], {}).get("residents", []).size()
	var lairs: Array = []
	var bandits := 0
	for faction: Dictionary in scenario.get("factions", []):
		if str(faction.kind) == "bandit": lairs.append(Vector2i(int(faction.bandit.lair.site[0]), int(faction.bandit.lair.site[1])))
	for team: Dictionary in scenario.get("teams", []):
		if int(team.faction_id) > 100: bandits += team.members.size()
	return {"ok": true, "path": path, "start": Vector2i(int(start[0]), int(start[1])), "settlements": settlements, "lairs": lairs, "residents": residents, "bandits": bandits, "seconds": 0.0}

func _run() -> void:
	var settlements := _arg("settlements", 6)
	var bands := _arg("bands", 3)
	var towns := _arg("towns", 1)
	var folder := "user://scenario_trial_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "package folder"): return
	var package_path := _text_arg("package")
	var built: Dictionary = _built_from(package_path) if not package_path.is_empty() else Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", settlements, bands, towns, 20261122)
	if not _ok(built.get("ok", false), "the generator builds %d settlements and %d bands" % [settlements, bands], built): return
	var package := RegionData.new()
	var loaded: Dictionary = package.load_manifest(str(built.path))
	var scenario: Dictionary = package.author_scenario()
	if not _ok(loaded.ok and scenario.get("factions", []).size() == settlements / 2 + settlements % 2 + bands and package.author_initial_context().expected_initial_sites.size() == 1 + settlements + bands,
		"the package loads with every Site and the scenario", [loaded, package.author_initial_context().get("expected_initial_sites", []).size()]): return
	var start: Vector2i = built.start
	# Step 6: the menu's scenario list reads the package (<root>/<id>/<id>.json with a scenario file).
	var listed: Array = RegionEntry.scenario_packages(folder if package_path.is_empty() else package_path.get_base_dir().get_base_dir())
	if not _ok(listed.size() == 1 and str(listed[0].id) == "demo_a" and listed[0].start == start and str(listed[0].name) == "開墾之地" and str(listed[0].record.id) == "demo_a_kaiken", "the scenario list finds the package with its start", listed): return
	if not _ok(RegionEntry.request_new_world(start, {}, "開墾試生", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	var birth_started := Time.get_ticks_msec()
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(36000):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
		if current_scene != null and current_scene.name == "MainMenu": break
	var birth_seconds := float(Time.get_ticks_msec() - birth_started) / 1000.0
	var shown: Node = current_scene.find_child("MenuMessage", true, false) if current_scene != null else null
	if not _ok(lab != null, "the world is born and opens (%.1f s)" % birth_seconds, (shown as Label).text if shown is Label else RegionEntry.menu_message): return
	for _frame: int in range(5): await process_frame
	preload("res://scripts/terrain_lab/perf_trace.gd").flush("scenario_trial") # with -- --perf-trace: where the birth time goes
	var controller: SiteController = lab.site_controller
	var slot: RegionSaveSlot = controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var named := true
	var chiefs := true
	for faction: Dictionary in scenario.factions:
		var entry: Dictionary = registry.entries.get(str(int(faction.id)), {})
		named = named and str(entry.get("name", "")) == str(faction.name) and str(entry.get("kind", "")) == str(faction.kind)
		if str(faction.kind) == "bandit": chiefs = chiefs and RegionPeerage.world_person_id(entry.get("leader_ref")) > 0
	if not _ok(named and chiefs, "every scenario faction is named and typed, every band has a chief"): return
	# The first generation of every settlement and lair Site.
	var residents := 0
	var settled := true
	for site: Vector2i in built.settlements:
		var cold: Dictionary = slot._load_checked(slot.site_path(site), site) if site != start else {"ok": true, "data": lab.terrain}
		if not cold.get("ok", false):
			settled = false
			break
		var state: Dictionary = cold.data.site
		residents += state.get("housing", {}).size()
		var head := int(SiteOffices.head_position(state.get("settlement", {}).get("offices", {})).get("holder", -1))
		var armed := false
		for army: Dictionary in state.get("armies", []): armed = armed or str(army.get("role", "")) == "combat"
		var stocked := false
		for key: String in state.get("stockpiles", {}): stocked = stocked or int(state.stockpiles[key].get("cargo", {}).get("grain", 0)) > 0
		settled = settled and head > 0 and armed and stocked
	if not _ok(settled and residents == int(built.residents), "every settlement has its housed residents, head, militia and stocked warehouse (%d residents)" % residents): return
	var lairs_ok := true
	for lair: Vector2i in built.lairs:
		var cold: Dictionary = slot._load_checked(slot.site_path(lair), lair)
		var band_team := false
		if cold.get("ok", false):
			for army: Dictionary in cold.data.site.get("armies", []): band_team = band_team or int(army.get("faction_id", 0)) > 100
		lairs_ok = lairs_ok and band_team
	if not _ok(lairs_ok, "every lair has its band team"): return
	var save_started := Time.get_ticks_msec()
	var saved: Dictionary = controller.save_to(controller.save_path)
	var save_seconds := float(Time.get_ticks_msec() - save_started) / 1000.0
	if not _ok(saved.ok, "the world saves (%.1f s)" % save_seconds, saved): return
	print("SCENARIO_TRIAL_TIMES generate=%.1f birth=%.1f save=%.1f settlements=%d bands=%d residents=%d bandits=%d" % [float(built.seconds), birth_seconds, save_seconds, settlements, bands, int(built.residents), int(built.bandits)])
	_finished = true
	TerrainArmy.release_contact_source()
	await process_frame
	print("SCENARIO_TRIAL_PASS: ", checks, " checks")
	quit(0)
