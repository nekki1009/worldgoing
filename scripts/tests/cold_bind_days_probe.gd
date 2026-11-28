extends SceneTree
## Probe (2026-11-25): binding a village nobody opened after `--days=N` game days. Prints what the long-absence admission
## sees at the first replay slices, and how the replay went. `--raid=1` lets bands raid it meanwhile (default: they lie low).
## Output: COLD_BIND lines and COLD_BIND_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const DAY := 86400.0

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

func _initialize() -> void:
	create_timer(3000.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _arg(name: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return float(arg.trim_prefix("--%s=" % name))
	return fallback

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("COLD_BIND END %s" % reason)
	print("COLD_BIND_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

func _inspect(child: TerrainLab) -> Dictionary:
	var controller: SiteController = child.site_controller
	var facts := {"inputs": child.region_cold_original_inputs(), "admission": child._region_cold_quiet_admission(),
		"paused": bool(child.terrain.site.get("paused", false)), "tree_paused": paused, "point": child._region_point_pending.size(), "contacts": child._combat_contacts.size(),
		"deaths": controller._pending_deaths.size(), "shared_plan": child._shared_work_plan.size(), "movement_prepared": child._shared_movement_prepared, "fatigue_work": child._fatigue_work_seconds.size(),
		"jobs": controller.person_actions._jobs.size(), "work_ids": controller.work_team.active_ids().size(), "projectiles": child.fire_projectiles.size(), "reservations": child.fire_reservations.size(),
		"boundary": child.terrain.get_meta(&"fire_boundary", {}).size(), "fire_committing": child._fire_committing, "fire_advancing": child._fire_advancing,
		"grid_armies": child.combat_armies.filter(func(team: TerrainArmy) -> bool: return team.has_army()).size(), "combat_left": float(child.terrain.site.get("combat_left", 0.0)),
		"fire_activity": child._fire_activity(), "siege": child._siege_active(), "crowd": child.crowd_site != null and child.crowd_site.active, "coarse": child._region_cold_isolated.get("coarse"),
		"unrecoverable": child._fire_replay_boundaries_unrecoverable, "segments": child._fire_replay_segments.size()}
	var jobs: Array = []
	for key: Variant in controller.person_actions._jobs: jobs.append(str(controller.person_actions._jobs[key].get("kind", "")))
	facts["job_kinds"] = jobs.slice(0, 6)
	return facts

func _run() -> void:
	var folder := "user://cold_bind_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
	var natural := RegionData.new()
	natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 4, 1, 0, 20261122)
	if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "久未打開", "", str(built.path)):
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
	if _arg("raid", 0.0) <= 0.0:
		for key: Variant in slot.control.faction_registry.entries:
			var band := int(slot.control.faction_registry.entries[key].faction_id)
			if not RegionFactionQuery.is_bandit(slot.control.faction_registry, band): continue
			lab.site_controller._commit_diplomacy(Bandit.set_heat(slot.control.faction_registry, band, 80, float(slot.control.logical_game_seconds)), "")
	var village := ""
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if loaded.ok and Settlement.record(loaded.data).has("owner_faction") and village.is_empty(): village = "%s:%s" % [str(slot.pin.atlas_id), str(site)]
	lab.simulation_speed = 16.0
	var began := float(slot.control.logical_game_seconds)
	var days := _arg("days", 2.0)
	var next_save := 1.0
	while float(slot.control.logical_game_seconds) - began < days * DAY:
		await process_frame
		if finished: return
		lab._process(1.0 / 30.0)
		lab.site_controller.person_actions.settle_after_contacts()
		if not lab.site_controller._original_step_fault.is_empty():
			_end("fault %s" % str(lab.site_controller._original_step_fault).left(300))
			return
		if (float(slot.control.logical_game_seconds) - began) / DAY >= next_save:
			var saved: Dictionary = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
			if saved.get("ok", false): next_save += 1.0
	print("COLD_BIND RAN days %.2f rows %d raids %s" % [(float(slot.control.logical_game_seconds) - began) / DAY, slot.control.fire_clock.journal.size(), JSON.stringify(slot.get_meta(&"bandit_formula_last", {})).left(200)])
	lab.set_process(false)
	var bound: Dictionary = {}
	var isolated: Dictionary = {}
	var bind_ms := Time.get_ticks_msec()
	var shown := 0
	var inside_ms := 0
	for attempt: int in range(20000):
		var call_ms := Time.get_ticks_msec()
		bound = lab._region_gameplay_owner_lab(village, "cold_exact")
		call_ms = Time.get_ticks_msec() - call_ms
		inside_ms += call_ms
		if attempt % 10 == 0: print("COLD_BIND TICK %d call %d ms total %d ms pending %s replay %s" % [attempt, call_ms, inside_ms, str(bound.get("pending")), JSON.stringify(bound.get("cold_replay", {})).left(300)])
		if is_instance_valid(lab._cold_replay_lab):
			isolated = lab._cold_replay_lab._region_cold_isolated.duplicate()
			if shown < 2:
				shown += 1
				print("COLD_BIND SLICE %d %s" % [attempt, JSON.stringify(_inspect(lab._cold_replay_lab)).left(2200)])
			if attempt % 500 == 0: print("COLD_BIND PROGRESS %d %s" % [attempt, JSON.stringify({"prefix": isolated.get("prefix_steps"), "exact": isolated.get("exact_steps"), "fallback": isolated.get("fallback"), "pending": bound.get("pending")})])
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	print("COLD_BIND BOUND ok=%s code=%s %d ms %s" % [str(bound.get("ok")), str(bound.get("code", "")), Time.get_ticks_msec() - bind_ms, JSON.stringify(isolated.duplicate()).left(600)])
	_end("complete")
