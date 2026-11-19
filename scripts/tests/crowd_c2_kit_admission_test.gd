extends SceneTree
## Existing validated capture kits are ready before the first action; warming never commits a person event.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
var lab: TerrainLab
var checks := 0
var missing_cache := false

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("KIT ADMISSION ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(2)
	return ok

func _assert_ready(site: Node, phase: String) -> bool:
	var cold: Dictionary = lab.terrain.site.duplicate(true)
	var blob: PackedByteArray = site.crowd.save_state()
	var kit_ids: PackedInt32Array = site._kit_ids.duplicate()
	var cache_size: int = site._kit_cache.size()
	var projected_keys := {}
	var started := Time.get_ticks_usec()
	for team: Dictionary in site.command_teams():
		for identity: int in site._team_by_id(int(team.team_id)).person_ids:
			var index: int = site.crowd.soldier_index(identity)
			var person: Dictionary = site.person_owner(identity).person(index)
			var selected: Dictionary = lab.site_controller.person_actions._sealed_selection(person)
			var projected: Dictionary = site._captivity_appearance(identity, person.holder, selected.item_ids)
			var key := JSON.stringify(projected)
			projected_keys[key] = true
			if not check(site._kit_cache.has(key), phase + " exact original-holder capture kit exists before first event", {"id": identity, "key": key}): return false
			var cached: int = site._kit_cache[key]
			var admitted: Dictionary = site._captivity_atlas_guard(identity, projected)
			if not check(admitted.ok and cached >= 0 and site._ensure_kit(projected) == cached, phase + " event guard reuses validated registered kit", identity): return false
			var descriptor: Dictionary = site.view._describe(projected)
			if not check(not descriptor.is_empty() and site.view._pages[int(descriptor.page)].texture != null and site.view._pages[int(descriptor.page)].mask_texture != null, phase + " exact page and dye mask remain admitted", identity): return false
	# The two factions share geometry but keep distinct palettes for both bodies.
	if not check(projected_keys.size() == 4, phase + " both bodies and faction palettes prewarm separately", projected_keys.size()): return false
	site._prewarm_captivity_atlases()
	if not check(site._kit_cache.size() == cache_size and site._kit_ids == kit_ids and not site._kit_ids_dirty and site.pending_captivity.is_empty() and site._captivity_atlas_jobs.is_empty(), phase + " repeated prewarm is cache-only and preserves the installed person matrix"): return false
	if not check(site.crowd.save_state() == blob and lab.terrain.site == cold and site.crowd.validate(), phase + " native HP/state and original item/supply ownership are unchanged"): return false
	print("KIT ADMISSION ", phase, " cached_guard_and_validation_usec=", Time.get_ticks_usec() - started, " registered_kits=", cache_size)
	return true

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: printerr("GATE FAIL: kit admission deadline"); quit(3))
	var args := OS.get_cmdline_user_args()
	missing_cache = args.has("--kit-missing-cache")
	if not check(args.has("--crowd") and args.has("--crowd-test") and args.has("--crowd-atlas-root"), "explicit isolated crowd and atlas paths required"): return
	var root_at := args.find("--crowd-atlas-root")
	if not check(root_at + 1 < args.size(), "atlas argument has a value"): return
	var atlas_root := args[root_at + 1]
	if missing_cache and not check(DisplayServer.get_name() == "headless" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(atlas_root)), "missing-cache control requires a new absent root and headless"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 2, "female_percent": 50, "attack": false, "ai_enabled": false, "entry": "west"},
		{"faction": 1, "count": 2, "female_percent": 50, "attack": false, "ai_enabled": false, "entry": "east"}])
	if not check(deployed.ok, "original deployment admitted", deployed): return
	var site: Node = lab.crowd_site
	if not check(site.active and site._steps == 0 and site._kit_ids.size() == site.crowd.soldier_count() and not site._kit_ids_dirty, "initial person kit matrix is installed before action"): return
	if missing_cache:
		var native: PackedByteArray = site.crowd.save_state()
		var original: Dictionary = lab.terrain.site.duplicate(true)
		var ids: PackedInt32Array = site._kit_ids.duplicate()
		var count: int = site._kit_cache.size()
		var identity: int = site._team_by_id(int(site.command_teams()[0].team_id)).person_ids[0]
		var index: int = site.crowd.soldier_index(identity)
		var person: Dictionary = site.person_owner(identity).person(index)
		var selection: Dictionary = lab.site_controller.person_actions._sealed_selection(person)
		var appearance: Dictionary = site._captivity_appearance(identity, person.holder, selection.item_ids)
		var rejected: Dictionary = site._captivity_atlas_guard(identity, appearance)
		if not check(not rejected.ok and rejected.code == "MISSING_ASSET" and site._ensure_kit(appearance) == -1 and not site._kit_cache.has(JSON.stringify(appearance)), "absent exact publication fails admission without borrowing dressed pixels", rejected): return
		site._prewarm_captivity_atlases()
		if not check(site.crowd.save_state() == native and lab.terrain.site == original and site._kit_ids == ids and site._kit_cache.size() == count and site.pending_captivity.is_empty() and site._captivity_atlas_jobs.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(atlas_root)), "headless missing cache changes no person, transaction, native state or disk cache"): return
	else:
		if not _assert_ready(site, "deploy"): return
		var appearance: Dictionary = site._appearance(int(site._records.keys()[0])).duplicate(true)
		appearance.equipment_dyes = {"weapon": "invalid_color"}
		var count: int = site._kit_cache.size()
		if not check(site._ensure_kit(appearance) == -1 and site._kit_cache.size() == count, "invalid dye never becomes a cached kit"): return
		var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
		if not check(saved.ok, "full original Site save before load admission", saved): return
		var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
		if not check(loaded.ok, "full original Site load rebuilds render cache", loaded): return
		site = lab.crowd_site
		if not _assert_ready(site, "load"): return
	lab.queue_free()
	await process_frame
	print("GATE OK: captivity kit admission ", "missing-cache" if missing_cache else "existing-cache", " ", checks)
	quit(0)
