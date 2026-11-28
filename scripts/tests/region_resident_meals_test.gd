extends SceneTree
## 居民吃飯 F1 (reports/scenario-village-livelihood-plan.md). A small generated scenario world; a settlement is bound as a
## cold owner. Checks, there:
## - without `meals` nobody is fed and nothing moves;
## - with it every household's pantry and every team's stock is filled from the settlement's own stock, real food only
##   (what is in the stock, the pantries and the teams together does not change);
## - in two game days people eat about one ration a day each, nobody goes hungry or dies, and it all saves and loads;
## - with nothing left to give, hunger grows and the short rations are counted.
## Output: REGION_RESIDENT_MEALS_PASS on success; quit(1) on any failure or the deadline.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const ResidentLife = preload("res://scripts/terrain_lab/site_resident_life.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")

var checks := 0
var _finished := false
var lab: TerrainLab
var slot: RegionSaveSlot

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _fail("1500-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> bool:
	if _finished: return false
	_finished = true
	push_error("REGION_RESIDENT_MEALS_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_RESIDENT_MEALS OK ", checks, ": ", message)
		return true
	return _fail(message, detail)

func _bind(id: String) -> Dictionary:
	lab.set_process(false)
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(id, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	lab.set_process(true)
	return bound

func _frame() -> bool:
	await process_frame
	if _finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty(): return _fail("a step fault", lab.site_controller._original_step_fault)
	return true

func _team_of(field: TerrainLab, person: int) -> Dictionary:
	for team: Dictionary in field.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(person): return team
	return {}

## The armed people of `faction` who are not captains, sorted.
func _soldiers(field: TerrainLab, faction: int) -> Array[int]:
	var found: Array[int] = []
	for team: Dictionary in field.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != faction or team.get("person_ids", []).size() < 2: continue
		var captain := int(field.site_controller.team_captain_of_team(int(team.team_id)))
		for person: Variant in team.get("person_ids", []):
			if int(person) == captain: continue
			var body: Dictionary = field.site_controller.person_actions._person(int(person), false)
			if body.is_empty() or float(body.get("hp", 0.0)) <= 0.0 or SiteOffices.body_military_role(body.get("body")) == "civilian": continue
			found.append(int(person))
	found.sort()
	return found

func _band_saved(band: int, lair: String, origin: String) -> bool:
	var registry: Dictionary = slot.control.faction_registry
	if not RegionFactionQuery.is_bandit(registry, band): return false
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	return str(table.get("origin", "")) == origin and table.get("lair") is Dictionary and str(table.lair.site_id) == lair

func _run() -> void:
	# The scenario key `livelihood`: {site, farms, camp}, one row a Site.
	var row := {"site": [1169, 13251], "farms": ["5", "6"], "camp": {"tools": 3, "seeds": 30}}
	if not _ok(RegionData._scenario_livelihood_valid([row]) and RegionData._scenario_livelihood_valid([]), "a livelihood row is valid"): return
	for wrong: Variant in [[row, row], {}, [{"site": [1169, 13251], "farms": ["5"]}], [row.merged({"camp": {"tools": 0}}, true)], [row.merged({"camp": {"": 1}}, true)], [row.merged({"farms": [5]}, true)], [row.merged({"farms": "5"}, true)], [row.merged({"site": [1169]}, true)], [row.merged({"extra": 1})]]:
		if not _ok(not RegionData._scenario_livelihood_valid(wrong), "refused: %s" % JSON.stringify(wrong)): return
	var folder := "user://meals_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _ok(DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a")) == OK, "scratch folder"): return
	var natural := RegionData.new()
	if not _ok(bool(natural.load_manifest(RegionData.DEFAULT_MANIFEST).ok), "the Taiwan source loads"): return
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, 20261122)
	if not _ok(built.get("ok", false), "the generator builds a small world", built): return
	if not _ok(RegionEntry.request_new_world(built.start, {}, "居民吃飯", "", str(built.path)), "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 900000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _ok(lab != null, "the world is born and opens"): return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	var here := str(lab.terrain.site.id)
	# Every band lies low: nothing else is bound or raided meanwhile.
	for key: Variant in slot.control.faction_registry.entries:
		var lying := int(slot.control.faction_registry.entries[key].faction_id)
		if not RegionFactionQuery.is_bandit(slot.control.faction_registry, lying): continue
		var hot: Dictionary = Bandit.set_heat(slot.control.faction_registry, lying, 80, float(slot.control.logical_game_seconds))
		if not _ok(hot.ok and lab.site_controller._commit_diplomacy(hot, "").ok, "band %d lies low" % lying, hot): return
	# The settlement with the most soldiers, but not a town's garrison.
	var village := ""
	var most := 0
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2 or "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]] == here: continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var armed := 0
		for army: Variant in loaded.data.site.get("armies", []):
			if not army is Dictionary: continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary and str(unit.get("military_role", "")) != "civilian": armed += 1
		if armed > most:
			most = armed
			village = "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
	if not _ok(not village.is_empty() and most >= 8, "a settlement with soldiers: %s (%d)" % [village, most]): return
	var bound: Dictionary = await _bind(village)
	if not _ok(bound.get("ok", false), "it is bound as a cold owner", bound): return
	var field: TerrainLab = slot._region_original_labs[village]
	var cold: SiteController = field.site_controller
	var owner := int(field.terrain.site.settlement.owner_faction)
	var site: Dictionary = field.terrain.site
	var food_of := func() -> float:
		var total := 0.0
		for item: String in SiteSustain.FOODS:
			total += float(site.get("inventory", {}).get(item, 0))
			for key: String in ResidentLife._warehouses(site, owner): total += float(site.stockpiles[key].cargo.get(item, 0))
		for entry: Dictionary in site.get("team_supply", {}).values():
			if int(entry.version) == 3:
				for location: Dictionary in entry.locations.values():
					total += float(location.open_rations)
					for item: String in SiteSustain.FOODS: total += float(location.inventory.get(item, 0))
			else:
				total += float(entry.sustain.get("open_rations", 0.0))
				for item: String in SiteSustain.FOODS: total += float(entry.inventory.get(item, 0))
		return total
	var living := func() -> int:
		var count := 0
		for team: Dictionary in field.crowd_site.teams:
			if bool(team.get("departed", false)) or int(team.get("faction", -1)) != owner: continue
			for person: Variant in team.get("person_ids", []):
				if float(field.crowd_site.combat_target(int(person)).get("hp", 0.0)) > 0.0: count += 1
		return count
	var hungriest := func() -> float:
		var worst := 0.0
		for entry: Dictionary in site.get("team_supply", {}).values():
			for cohort: Dictionary in entry.sustain.cohorts: worst = maxf(worst, float(cohort.hunger))
		return worst
	lab.set_process(false)
	# A scenario settlement serves meals and works its fields from its birth.
	if not _ok(int(site.settlement.get("meals", 0)) == 1 and not site.get("households", {}).is_empty() and site.households.values().any(func(house: Dictionary) -> bool: return str(site.features.get(str(house.job.feature), {}).get("kind", "")) == "farm"), "its households have fields to work", site.get("households", {})): return
	site.settlement.erase("meals")
	if not _ok(int(ResidentLife.ration_day(cold).moved) == 0, "without `meals` nothing is given"): return
	# No harvest while the eating is counted.
	for item: String in ["seeds", "tools"]: site.inventory.erase(item)
	var people: int = living.call()
	var pace := func() -> float: # real milliseconds a frame over 300 frames
		lab.set_process(true)
		lab.simulation_speed = 16.0
		var pace_from := Time.get_ticks_usec()
		for step: int in 300:
			if not await _frame(): return -1.0
		return float(Time.get_ticks_usec() - pace_from) / 300000.0
	slot.set_meta(&"bandit_musters", {village: 1000000}) # kept bound: the idle release would close it after six hours
	var pace_off: float = await pace.call()
	lab.set_process(false)
	site.settlement["meals"] = 1
	site["inventory"]["grain"] = int(site.get("inventory", {}).get("grain", 0)) + people * 12
	var before: float = food_of.call()
	var given: Dictionary = {}
	for attempt: int in range(900):
		given = ResidentLife.ration_day(cold)
		if given.refused.is_empty(): break
		if not await _frame(): return
	if not _ok(given.refused.is_empty(), "the rations of the day are given", given): return
	var ledger: Dictionary = site.get("team_supply", {})
	var kinds: Array = ledger.values().map(func(entry: Dictionary) -> int: return int(entry.version))
	if not _ok(kinds.has(3) and kinds.has(2), "the residents eat from their pantries, the armed teams from their own stock", kinds): return
	if not _ok(absf(float(food_of.call()) - before) < 0.001 and int(given.short) == 0, "no food came or went by it", [before, food_of.call(), given]): return
	var again: Dictionary = ResidentLife.ration_day(cold)
	if not _ok(int(again.moved) == 0 and again.refused.is_empty(), "asked again the same day there is nothing to add", again): return

	print("REGION_RESIDENT_MEALS PACE %.1f ms a frame without meals, %.1f with" % [pace_off, await pace.call()])
	if _finished: return
	before = food_of.call()
	# Two days.
	var from := float(slot.control.logical_game_seconds)
	var began := Time.get_ticks_msec()
	for frame: int in range(400000):
		if not await _frame(): return
		if float(slot.control.logical_game_seconds) - from >= 2.0 * Bandit.DAY: break
		if not is_instance_valid(slot._region_original_labs.get(village)):
			_ok(false, "the settlement stays bound")
			return
	var eaten: float = before - float(food_of.call())
	print("REGION_RESIDENT_MEALS DAYS people %d eaten %.2f hungriest %.1f in %d s, %s" % [people, eaten, hungriest.call(), (Time.get_ticks_msec() - began) / 1000, str(cold.last_rations)])
	if not _ok(int(living.call()) == people, "everybody is alive", [living.call(), people]): return
	if not _ok(eaten > float(people) * 1.7 and eaten <= float(people) * 2.4, "they ate about a ration a day each: %.1f by %d people in 2 days" % [eaten, people]): return
	if not _ok(float(hungriest.call()) < 18.0, "nobody is hungry", hungriest.call()): return
	var saved: Dictionary = {}
	for attempt: int in range(300):
		saved = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
		if saved.get("ok", false): break
		if not await _frame(): return
	var parts: PackedStringArray = village.split(":")
	var key := "%s:%s" % [parts[parts.size() - 2], parts[parts.size() - 1]]
	var file: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[key].path)), Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1])))
	if not _ok(saved.get("ok", false) and file.ok and int(file.data.site.settlement.get("meals", 0)) == 1 and file.data.site.team_supply.size() == ledger.size(), "it saves and loads", [saved, file.get("code")]): return

	# Nothing left to give.
	for item: String in SiteSustain.FOODS:
		site.inventory.erase(item)
		for at: String in ResidentLife._warehouses(site, owner): site.stockpiles[at].cargo.erase(item)
	var short: Dictionary = ResidentLife.ration_day(cold)
	if not _ok(int(short.moved) == 0 and int(short.short) > 0, "with an empty stock the missing rations are counted", short): return
	TerrainArmy.release_contact_source()
	await process_frame
	_finished = true
	print("REGION_RESIDENT_MEALS_PASS: ", checks, " checks")
	quit(0)
