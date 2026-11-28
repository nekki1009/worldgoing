extends SceneTree
## Probe (2026-11-25): why a band cannot leave its bound lair (REGION_BACKEND_UNADMITTED, found by
## bandit_raid_calibration_probe.gd). A small generated world, the lair bound and published; each step of the dispatch is
## called by itself and printed. `--stay=N` keeps N of the lair's people in a one-person team of their own (is it the empty
## Site?). Output: RAID_DISPATCH lines and RAID_DISPATCH_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

func _initialize() -> void:
	create_timer(1500.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _arg(name: String, fallback: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return int(arg.trim_prefix("--%s=" % name))
	return fallback

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("RAID_DISPATCH END %s" % reason)
	print("RAID_DISPATCH_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

func _say(step: String, value: Variant) -> void:
	print("RAID_DISPATCH %s %s" % [step, str(value).left(500)])

func _run() -> void:
	var folder := "user://raid_dispatch_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
	var natural := RegionData.new()
	natural.load_manifest(RegionData.DEFAULT_MANIFEST)
	var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 4, 1, 0, 20261122)
	if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "出門追查", "", str(built.path)):
		_end("no world %s" % str(built).left(200))
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
	var band := -1
	for key: Variant in registry.entries:
		if registry.entries[key].get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(registry.entries[key].faction_id)): band = int(registry.entries[key].faction_id)
	var lair := str(RegionFactionQuery.bandit_of(registry, band).lair.site_id)
	lab.set_process(false)
	var bound: Dictionary = {}
	for attempt: int in range(6000):
		bound = lab._region_gameplay_owner_lab(lair, "cold_exact")
		if bound.get("ok", false) or str(bound.get("code", "")) != "PENDING": break
		await process_frame
	if not bound.get("ok", false):
		_end("lair %s" % str(bound).left(300))
		return
	var home: TerrainLab = bound.lab
	var target := ""
	for site: Variant in slot._marker.sites:
		var id := "%s:%s" % [str(slot.pin.atlas_id), str(site)]
		if id == lair or id == str(lab.terrain.site.id): continue
		if target.is_empty() or Bandit.site_distance(lair, id) < Bandit.site_distance(lair, target): target = id
	var parts := target.split(":")
	var goal := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	for team: Dictionary in home.crowd_site.teams: _say("TEAM", {"team": team.team_id, "faction": team.faction, "people": team.person_ids.size(), "solo": team.get("solo", false), "departed": team.get("departed", false)})
	_say("SOURCE before", home._region_selected_bind_source(home.terrain, slot))
	_say("UNPUBLISHED", slot._region_cold_unpublished(home))
	var published: Dictionary = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
	_say("PUBLISH", published)
	_say("SOURCE after", home._region_selected_bind_source(home.terrain, slot))
	if _arg("stay", 0) > 0:
		var multi: Dictionary = {}
		for team: Dictionary in home.crowd_site.teams:
			if team.person_ids.size() > 2: multi = team
		var stays: int = int(multi.person_ids.back())
		_say("STAY", home.crowd_site.detach_to_new_team(stays, band))
		_say("PUBLISH 2", lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, ""))
	var leaving := -1
	for team: Dictionary in home.crowd_site.teams:
		if team.person_ids.size() >= 2 and not bool(team.get("departed", false)): leaving = int(team.team_id)
	var captain := int(home.site_controller.team_captain_of_team(leaving))
	var body: Dictionary = home.crowd_site.combat_target(captain)
	var here: Dictionary = slot._coordinate(home.terrain)
	var component: int = RegionTravelSite.start_component(slot, here.site, body.cell, home.terrain)
	var original: Callable = slot.region_bind_candidate
	slot.region_bind_candidate = func(of: TerrainLab, candidate: TerrainData, mode: String) -> Dictionary:
		_say("CANDIDATE", {"armies": candidate.site.get("armies", []).size(), "has_crowd": candidate.site.has("crowd"), "people": candidate.site.get("crowd", {}).get("teams", []).size()})
		var source: TerrainData = candidate.get_meta(&"region_bind_source", candidate)
		# The same steps as TerrainLab._region_prepare_original_bind, one by one.
		var selected := of._region_selected_bind_source(source, slot)
		_say("STEP selected", {"ok": selected.ok, "code": selected.get("code", "")})
		if selected.ok:
			var source_copy := of._region_detached_bind_data(selected.get("canonical_data", source))
			var child_made := of._region_new_bind_child(source_copy)
			var restored: Dictionary = of._region_bootstrap_bind_child(child_made.child, source_copy)
			_say("STEP bootstrap", {"ok": restored.ok, "code": restored.get("code", ""), "backend": restored.get("context", {}).get("backend", "")})
			if restored.ok:
				var target_copy := of._region_detached_bind_data(candidate)
				target_copy.site.erase("region_snapshot")
				var projection: Dictionary = of._region_project_original_bind_child(child_made.child, target_copy, restored.context)
				_say("STEP projection", {"ok": projection.ok, "code": projection.get("code", ""), "message": projection.get("message", "")})
				_say("STEP child", {"crowd": child_made.child.crowd_site != null and child_made.child.crowd_site.active, "site_has_crowd": child_made.child.terrain.site.has("crowd"), "rosters": child_made.child.crowd_site.rosters.size() if child_made.child.crowd_site != null else -1})
			child_made.child.free()
		var result: Dictionary = original.call(of, candidate, mode)
		_say("BIND result", {"ok": result.ok, "code": result.get("code", ""), "message": result.get("message", "")})
		return result
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(home, "captain:band", leaving, goal, component, [], "band_raid_trace")
	_say("PREPARED", {"ok": prepared.get("ok"), "code": prepared.get("code", ""), "message": prepared.get("message", "")})
	if prepared.get("ok", false):
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		_say("COMMITTED", {"ok": committed.get("ok"), "code": committed.get("code", ""), "message": committed.get("message", "")})
		lab.set_process(true)
		for frame: int in range(3000):
			await process_frame
			lab._process(1.0 / 30.0)
			lab.site_controller.person_actions.settle_after_contacts()
			if not lab.site_controller._original_step_fault.is_empty(): break
			if frame % 300 == 0:
				var at_home: Variant = slot._region_original_labs.get(lair)
				_say("FRAME %d" % frame, {"hours": float(slot.control.logical_game_seconds) / 3600.0, "bound": slot._region_original_labs.keys(), "home_people": at_home.crowd_site._index_by_id.size() if at_home != null and at_home.crowd_site != null and at_home.crowd_site.active else 0, "mode": slot.region_registry().modes.get(lair, {}).get("backend", "")})
		_say("FAULT", lab.site_controller._original_step_fault)
	_end("complete")
