extends SceneTree
## Probe (headless): which captive looks a born world of a scenario package needs. Births the package (default the
## shipped demo A) through the real boot path, then reads every Site file of the slot and projects each roster person's
## look from his items (SiteRuntime.equipment_appearance), stripped of weapon and shield exactly as
## CrowdSite._prewarm_captivity_atlases strips it, and keys it by the mixed atlas key (geometry only; dyes are palettes).
## Prints CAPTIVE_LOOKS lines (persons, distinct keys, per Site) and writes the distinct stripped looks as a JSON array to
## `--out=<res://output/...json>` (default res://output/captive_looks/demo_a.json): the input of the bake tool
## (scripts/tools/bake_captivity_appearances.gd --appearances <path>). `--role=` picks the start as the capture does.
## Output: CAPTIVE_LOOKS_DONE; quit(1) when the world is not born.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	create_timer(840.0).timeout.connect(func() -> void:
		print("CAPTIVE_LOOKS deadline")
		quit(1))
	_run.call_deferred()

static func stripped(appearance: Dictionary) -> Dictionary:
	var look: Dictionary = appearance.duplicate(true)
	if not look.get("parts") is Dictionary: return {}
	for slot: String in ["weapon", "shield"]:
		look.parts[slot] = "none"
		if look.has("equipment_dyes"): look.equipment_dyes.erase(slot)
	if look.has("equipment_dyes") and look.equipment_dyes.is_empty(): look.erase("equipment_dyes")
	return look

func _run() -> void:
	var package := _arg("package", PACKAGE)
	var role := _arg("role", "leader")
	var out := _arg("out", "res://output/captive_looks/demo_a.json")
	var person: Dictionary = {}
	for row: Dictionary in ScenarioPeople.people(package).get("people", []):
		if str(row.role) == role:
			person = row
			break
	if person.is_empty() or not RegionEntry.request_new_world(person.site, {"name": str(person.name)}, "圖集清單", "", package, {"mode": "neutral"}, {"surname": str(person.name).left(1)}, {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}, [], {"name": str(person.name)}):
		print("CAPTIVE_LOOKS refused %s" % RegionEntry.menu_message)
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
		print("CAPTIVE_LOOKS not born")
		quit(1)
		return
	for _frame: int in range(5): await process_frame
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var looks := {}
	var covered := {}
	var persons := 0
	var mounted := 0
	var unsupported := 0
	var sites := 0
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2: continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok:
			print("CAPTIVE_LOOKS site %s not loaded: %s" % [str(site), str(loaded.get("code", ""))])
			continue
		sites += 1
		var data: TerrainData = loaded.data
		var here := {}
		for army: Variant in data.site.get("armies", []):
			if not army is Dictionary: continue
			for unit: Variant in army.get("units", []):
				if not unit is Dictionary or not unit.get("appearance") is Dictionary or not unit.get("item_state") is Dictionary: continue
				persons += 1
				var projected: Dictionary = SiteRuntime.equipment_appearance(data, unit.item_state, unit.appearance)
				if bool(projected.get("mounted", false)):
					mounted += 1
					continue
				var look := stripped(projected)
				var key := Atlas._mixed_key(look)
				if key.is_empty():
					unsupported += 1
					continue
				# A look an existing recipe already draws needs no bake; the rest is what the prewarm bakes (one per key).
				if Atlas.supports(look):
					if not covered.has(key): covered[key] = look
					continue
				here[key] = true
				if not looks.has(key): looks[key] = look
		print("CAPTIVE_LOOKS site %s: %d distinct" % [str(site), here.size()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var keys: Array = looks.keys()
	keys.sort()
	# Every distinct look goes to the bake tool, which bakes only those no recipe draws yet (an existing standard or
	# civilian recipe can still lack the mixed page the crowd batch view asks for).
	var listing: Array = []
	for key: Variant in keys: listing.append(looks[key])
	var covered_keys: Array = covered.keys()
	covered_keys.sort()
	for key: Variant in covered_keys: listing.append(covered[key])
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(listing, "", true))
	file.close()
	print("CAPTIVE_LOOKS %d Sites, %d persons: %d distinct captive looks to bake, %d already drawn by a recipe (%d mounted, %d without a key); keys %s; written %s" % [sites, persons, looks.size(), covered.size(), mounted, unsupported, JSON.stringify(keys).sha256_text().left(16), out])
	for key: Variant in keys: print("CAPTIVE_LOOKS bake %s body %s %s" % [str(key).left(12), str(looks[key].get("body")), JSON.stringify(looks[key].parts)])
	TerrainArmy.release_contact_source()
	await process_frame
	print("CAPTIVE_LOOKS_DONE")
	quit(0)
