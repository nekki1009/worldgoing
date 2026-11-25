extends SceneTree
## Probe (2026-11-25): what a real far raid of a lair's own band does, to set the formula of the raids nobody sees
## (Nekki 2026-11-25 B). A small generated scenario world opens; lair number `--lair=K` (by faction id) is bound as a cold
## owner and its team is sent to the settlement number `--target=J` by distance (site_bandit_far_raid.gd, the real path).
## Prints the people on both sides before and after, the deaths, the loot and the game hours.
## Output: RAID_CALIBRATION lines and RAID_CALIBRATION_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Attacked = preload("res://scripts/terrain_lab/site_bandit_attacked.gd")
const FarRaid = preload("res://scripts/terrain_lab/site_bandit_far_raid.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

func _initialize() -> void:
	create_timer(3400.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _arg(name: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return int(arg.trim_prefix("--%s=" % name))
	return fallback

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("RAID_CALIBRATION END %s" % reason)
	print("RAID_CALIBRATION_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

## The people on a bound Site by faction: {faction: {armed, civil, down, dead}} (dead: hp 0 bodies still listed).
func _people(field: TerrainLab) -> Dictionary:
	var result := {}
	for team: Dictionary in field.crowd_site.teams:
		if bool(team.get("departed", false)): continue
		var faction := int(team.get("faction", -1))
		if not result.has(faction): result[faction] = {"armed": 0, "civil": 0, "down": 0, "captive": 0, "dead": 0, "able": 0}
		for person: Variant in team.get("person_ids", []):
			if not field.crowd_site._index_by_id.has(int(person)): continue
			var state: Dictionary = field.crowd_site.soldier_state(int(field.crowd_site._index_by_id[int(person)]))
			var role := SiteOffices.body_military_role(field.site_controller.person_actions._person(int(person), false).get("body"))
			result[faction]["civil" if role == "civilian" else "armed"] += 1
			if float(state.get("hp", 0.0)) <= 0.0: result[faction].dead += 1
			elif float(state.get("captive", 0.0)) > 0.0: result[faction].captive += 1
			elif float(state.get("ko", 0.0)) > 0.0: result[faction].down += 1
			else: result[faction].able += 1
	return result

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
	if finished: return false
	lab._process(1.0 / 30.0)
	lab.site_controller.person_actions.settle_after_contacts()
	if not lab.site_controller._original_step_fault.is_empty():
		_end("step fault %s" % str(lab.site_controller._original_step_fault).left(300))
		return false
	return true

func _run() -> void:
	var folder := "user://raid_calibration_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
	var natural := RegionData.new()
	natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 6, 3, 1, _arg("seed", 20261122))
	if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "遠征校準", "", str(built.path)):
		_end("no world")
		return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 1200000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("the world did not open")
		return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var bands: Array[int] = []
	for key: Variant in registry.entries:
		if registry.entries[key].get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(registry.entries[key].faction_id)): bands.append(int(registry.entries[key].faction_id))
	bands.sort()
	var band := bands[clampi(_arg("lair", 0), 0, bands.size() - 1)]
	var lair := str(RegionFactionQuery.bandit_of(registry, band).lair.site_id)
	var targets: Array = []
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if parts.size() != 2: continue
		var id := "%s:%s:%s" % [str(slot.pin.atlas_id), parts[0], parts[1]]
		if id == str(lab.terrain.site.id) or id == lair: continue
		var began := Time.get_ticks_msec()
		var raw: Dictionary = slot._read_document(slot.folder.path_join(str(slot._marker.sites[site].path)), 67108864)
		print("RAID_CALIBRATION RAW %s read ok=%s in %d ms keys=%s" % [id, str(raw.get("ok")), Time.get_ticks_msec() - began, str(raw.get("payload", {}).keys()).left(300)])
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		var owner := int(Settlement.record(loaded.data).owner_faction)
		var counted := {"armed": 0, "civil": 0}
		for army: Variant in loaded.data.site.get("armies", []):
			if not army is Dictionary or int(army.get("faction_id", -1)) != owner: continue
			for unit: Variant in army.get("units", []):
				if unit is Dictionary: counted["civil" if str(unit.get("military_role", "")) == "civilian" else "armed"] += 1
		targets.append({"id": id, "distance": Bandit.site_distance(lair, id), "owner": owner, "people": counted, "stock": Aftermath.stock_of(loaded.data.site, owner)})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.distance) < int(b.distance) or int(a.distance) == int(b.distance) and str(a.id) < str(b.id))
	for row: Dictionary in targets: print("RAID_CALIBRATION SITE %s" % JSON.stringify(row))
	var target: Dictionary = targets[clampi(_arg("target", 0), 0, targets.size() - 1)]
	var bound: Dictionary = await _bind(lair)
	if not bound.get("ok", false):
		_end("lair %s" % str(bound).left(300))
		return
	var home: TerrainLab = bound.lab
	print("RAID_CALIBRATION LAIR band=%d %s people %s" % [band, lair, JSON.stringify(_people(home))])
	# A lair bound from its unopened file is published once first: its own file still carries the retired grid's capture, and
	# the dispatch refused it REGION_BACKEND_UNADMITTED (found 2026-11-25 by this probe's first run).
	var publish_began := Time.get_ticks_msec()
	var published: Dictionary = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
	print("RAID_CALIBRATION PUBLISH ok=%s code=%s %d ms with %d bound" % [str(published.get("ok")), str(published.get("code", "")), Time.get_ticks_msec() - publish_began, slot._region_original_labs.size()])
	lab.simulation_speed = 4.0
	var sent: Dictionary = {}
	var today := int(float(slot.control.logical_game_seconds) / Bandit.DAY)
	Attacked.note_raid(home.site_controller, band, str(target.id), today)
	for attempt: int in range(40):
		sent = FarRaid.raid(home.site_controller, band, {"site_id": str(target.id), "faction": int(target.owner)})
		if sent.get("ok", false): break
		for _wait: int in range(30):
			if not await _frame(): return
	if not sent.get("ok", false):
		_end("not sent %s" % str(sent).left(400))
		return
	var token := str(sent.sent[0].token)
	var started := float(slot.control.logical_game_seconds)
	for frame: int in range(200000):
		if not await _frame(): return
		if str(slot.region_registry().parties.get(token, {}).get("phase", "")) == "entered": break
	print("RAID_CALIBRATION ENTERED phase=%s after %.1f hours" % [str(slot.region_registry().parties.get(token, {}).get("phase", "")), (float(slot.control.logical_game_seconds) - started) / 3600.0])
	var field: TerrainLab = slot._region_original_labs.get(str(target.id))
	if field == null:
		_end("the target is not bound")
		return
	var first := _people(field)
	var hoard_before: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {}).duplicate()
	var stock_before: Dictionary = Aftermath.stock_of(field.terrain.site, int(target.owner))
	print("RAID_CALIBRATION FIELD before %s stock %s" % [JSON.stringify(first), JSON.stringify(stock_before)])
	var arrived := float(slot.control.logical_game_seconds)
	var fought := false
	var closed_at := -1.0
	var after_at := 0.0
	var told := false
	for frame: int in range(60000):
		if not await _frame(): return
		field = slot._region_original_labs.get(str(target.id))
		if field == null or field.crowd_site == null: break
		var hours := (float(slot.control.logical_game_seconds) - arrived) / 3600.0
		if field.crowd_site.battle.open and not fought:
			fought = true
			print("RAID_CALIBRATION BATTLE opens at %.2f hours" % hours)
		if fought and not field.crowd_site.battle.open and closed_at < 0.0:
			closed_at = hours
			print("RAID_CALIBRATION BATTLE closes at %.2f hours %s" % [hours, JSON.stringify(_people(field))])
		if not slot.get_meta(&"bandit_raid_outcome", {}).is_empty() and not told:
			told = true
			print("RAID_CALIBRATION OUTCOME at %.2f hours %s" % [hours, JSON.stringify(slot.get_meta(&"bandit_raid_outcome"))])
		if closed_at >= 0.0 and hours >= after_at:
			after_at = hours + 2.0
			var phases := {}
			for party: String in slot.region_registry().parties: phases[party.left(12)] = str(slot.region_registry().parties[party].get("phase", ""))
			print("RAID_CALIBRATION AFTER %.2f hours %s parties %s home %s" % [hours, JSON.stringify(_people(field)), JSON.stringify(phases), JSON.stringify(slot.get_meta(&"bandit_raid_home", {})).left(300)])
		if closed_at >= 0.0 and hours > closed_at + float(_arg("after", 20)): break
		if closed_at < 0.0 and hours >= 12.0: break
	if field != null:
		print("RAID_CALIBRATION FIELD after %s stock %s" % [JSON.stringify(_people(field)), JSON.stringify(Aftermath.stock_of(field.terrain.site, int(target.owner)))])
	print("RAID_CALIBRATION RESULT band=%d target=%s hoard %s -> %s raids_open %s" % [band, str(target.id), JSON.stringify(hoard_before), JSON.stringify(RegionFactionQuery.bandit_of(slot.control.faction_registry, band).get("hoard", {})), JSON.stringify(slot.get_meta(&"bandit_raids_open", {}))])
	_end("complete")
